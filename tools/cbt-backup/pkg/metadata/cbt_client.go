package metadata

import (
	"context"
	"crypto/tls"
	"crypto/x509"
	"encoding/base64"
	"fmt"
	"io"
	"time"

	csi "github.com/container-storage-interface/spec/lib/go/csi"
	"github.com/kaovilai/k8s-cbt-s3mover-demo/tools/cbt-backup/pkg/blocks"
	snapshotv1 "github.com/kubernetes-csi/external-snapshotter/client/v8/apis/volumesnapshot/v1"
	snapclientset "github.com/kubernetes-csi/external-snapshotter/client/v8/clientset/versioned"
	"google.golang.org/grpc"
	"google.golang.org/grpc/credentials"
	authv1 "k8s.io/api/authentication/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime/schema"
	"k8s.io/client-go/dynamic"
	"k8s.io/client-go/kubernetes"
	"k8s.io/client-go/rest"
	"k8s.io/client-go/tools/clientcmd"
)

// bearerToken implements grpc credentials.PerRPCCredentials for bearer token auth
type bearerToken struct {
	token string
}

func (t bearerToken) GetRequestMetadata(ctx context.Context, uri ...string) (map[string]string, error) {
	return map[string]string{
		"authorization": "Bearer " + t.token,
	}, nil
}

func (t bearerToken) RequireTransportSecurity() bool {
	return true
}

// CBTClient interfaces with the CSI SnapshotMetadata service
type CBTClient struct {
	conn               *grpc.ClientConn
	client             csi.SnapshotMetadataClient
	snapClient         *snapclientset.Clientset
	kubeClient         *kubernetes.Clientset
	dynClient          dynamic.Interface
	config             *rest.Config
	namespace          string
	serviceAccountName string
	socketAddress      string // override endpoint (skips discovery)
}

// NewCBTClient creates a new CBT client
// This implementation:
// 1. Creates a Kubernetes client for snapshot API
// 2. Discovers the SnapshotMetadataService endpoint
// 3. Establishes gRPC connection to the CSI driver
func NewCBTClient(namespace string, kubeconfig string, serviceAccountName string) (*CBTClient, error) {
	// Create Kubernetes config
	var config *rest.Config
	var err error

	if kubeconfig != "" {
		config, err = clientcmd.BuildConfigFromFlags("", kubeconfig)
	} else {
		config, err = rest.InClusterConfig()
	}
	if err != nil {
		return nil, fmt.Errorf("failed to create kubernetes config: %w", err)
	}

	// Create snapshot client
	snapClient, err := snapclientset.NewForConfig(config)
	if err != nil {
		return nil, fmt.Errorf("failed to create snapshot client: %w", err)
	}

	// Create core Kubernetes client (for SA token creation)
	kubeClient, err := kubernetes.NewForConfig(config)
	if err != nil {
		return nil, fmt.Errorf("failed to create kubernetes client: %w", err)
	}

	// Create dynamic client (for SnapshotMetadataService CR)
	dynClient, err := dynamic.NewForConfig(config)
	if err != nil {
		return nil, fmt.Errorf("failed to create dynamic client: %w", err)
	}

	if serviceAccountName == "" {
		serviceAccountName = "cbt-backup-sa"
	}

	client := &CBTClient{
		snapClient:         snapClient,
		kubeClient:         kubeClient,
		dynClient:          dynClient,
		config:             config,
		namespace:          namespace,
		serviceAccountName: serviceAccountName,
	}

	return client, nil
}

// SetEndpoint overrides the default gRPC endpoint address (skips service discovery)
func (c *CBTClient) SetEndpoint(endpoint string) {
	c.socketAddress = endpoint
}

// discoverService reads the SnapshotMetadataService CR to find the gRPC endpoint,
// CA certificate, and audience for token-based authentication.
func (c *CBTClient) discoverService(ctx context.Context) (address, caCertBase64, audience string, err error) {
	gvr := schema.GroupVersionResource{
		Group:    "cbt.storage.k8s.io",
		Version:  "v1alpha1",
		Resource: "snapshotmetadataservices",
	}

	list, err := c.dynClient.Resource(gvr).List(ctx, metav1.ListOptions{})
	if err != nil {
		return "", "", "", fmt.Errorf("failed to list SnapshotMetadataService resources: %w", err)
	}

	if len(list.Items) == 0 {
		return "", "", "", fmt.Errorf("no SnapshotMetadataService resources found")
	}

	// Use the first available service (typically there's only one)
	item := list.Items[0]
	spec, ok := item.Object["spec"].(map[string]interface{})
	if !ok {
		return "", "", "", fmt.Errorf("invalid SnapshotMetadataService spec")
	}

	address, _ = spec["address"].(string)
	caCertBase64, _ = spec["caCert"].(string)
	audience, _ = spec["audience"].(string)

	if address == "" {
		return "", "", "", fmt.Errorf("SnapshotMetadataService has no address")
	}

	fmt.Printf("Discovered SnapshotMetadataService: address=%s, audience=%s\n", address, audience)
	return address, caCertBase64, audience, nil
}

// createSAToken creates a service account token with the specified audience
func (c *CBTClient) createSAToken(ctx context.Context, audience string) (string, error) {
	audiences := []string{}
	if audience != "" {
		audiences = []string{audience}
	}

	tokenReq := &authv1.TokenRequest{
		Spec: authv1.TokenRequestSpec{
			Audiences: audiences,
		},
	}

	token, err := c.kubeClient.CoreV1().ServiceAccounts(c.namespace).CreateToken(
		ctx, c.serviceAccountName, tokenReq, metav1.CreateOptions{},
	)
	if err != nil {
		return "", fmt.Errorf("failed to create SA token for %s/%s: %w", c.namespace, c.serviceAccountName, err)
	}

	return token.Status.Token, nil
}

// Connect establishes the gRPC connection to the CSI driver
func (c *CBTClient) Connect(ctx context.Context) error {
	if c.conn != nil {
		return nil // Already connected
	}

	// Use a timeout to avoid hanging forever if the endpoint is unreachable
	connectCtx, cancel := context.WithTimeout(ctx, 30*time.Second)
	defer cancel()

	var address string
	var dialOpts []grpc.DialOption

	if c.socketAddress != "" {
		// Manual endpoint override — use insecure (for testing/debugging)
		address = c.socketAddress
		fmt.Printf("Using manually configured endpoint: %s\n", address)
		dialOpts = append(dialOpts,
			grpc.WithTransportCredentials(credentials.NewTLS(&tls.Config{InsecureSkipVerify: true})),
		)
	} else {
		// Discover service from SnapshotMetadataService CR
		svcAddress, caCertB64, audience, err := c.discoverService(connectCtx)
		if err != nil {
			return fmt.Errorf("failed to discover snapshot metadata service: %w", err)
		}
		address = svcAddress

		// Build TLS credentials from CA cert
		tlsConfig, err := buildTLSConfig(caCertB64)
		if err != nil {
			return fmt.Errorf("failed to build TLS config: %w", err)
		}
		dialOpts = append(dialOpts, grpc.WithTransportCredentials(credentials.NewTLS(tlsConfig)))

		// Create SA token for authentication
		token, err := c.createSAToken(connectCtx, audience)
		if err != nil {
			return fmt.Errorf("failed to create authentication token: %w", err)
		}
		dialOpts = append(dialOpts, grpc.WithPerRPCCredentials(bearerToken{token: token}))
		fmt.Println("Created SA token for gRPC authentication")
	}

	dialOpts = append(dialOpts, grpc.WithBlock())

	// Establish gRPC connection
	fmt.Printf("Connecting to CSI SnapshotMetadata service at %s...\n", address)
	conn, err := grpc.DialContext(
		connectCtx,
		address,
		dialOpts...,
	)
	if err != nil {
		return fmt.Errorf("failed to connect to CSI driver at %s: %w", address, err)
	}

	c.conn = conn
	c.client = csi.NewSnapshotMetadataClient(conn)
	fmt.Println("Connected to CSI SnapshotMetadata service")

	return nil
}

// buildTLSConfig creates a TLS config from a base64-encoded CA certificate
func buildTLSConfig(caCertBase64 string) (*tls.Config, error) {
	if caCertBase64 == "" {
		return &tls.Config{InsecureSkipVerify: true}, nil
	}

	caCertPEM, err := base64.StdEncoding.DecodeString(caCertBase64)
	if err != nil {
		return nil, fmt.Errorf("failed to decode CA cert: %w", err)
	}

	certPool := x509.NewCertPool()
	if !certPool.AppendCertsFromPEM(caCertPEM) {
		return nil, fmt.Errorf("failed to parse CA certificate")
	}

	return &tls.Config{
		RootCAs: certPool,
	}, nil
}

// GetAllocatedBlocks returns all allocated blocks in a snapshot
// This calls the CSI GetMetadataAllocated RPC
func (c *CBTClient) GetAllocatedBlocks(ctx context.Context, snapshotName string) ([]blocks.BlockMetadata, error) {
	if c.client == nil {
		return nil, fmt.Errorf("not connected to CSI driver - call Connect() first")
	}

	// Get VolumeSnapshot to extract CSI snapshot handle
	snapshot, err := c.snapClient.SnapshotV1().VolumeSnapshots(c.namespace).Get(ctx, snapshotName, metav1.GetOptions{})
	if err != nil {
		return nil, fmt.Errorf("failed to get VolumeSnapshot %s: %w", snapshotName, err)
	}

	if snapshot.Status == nil || snapshot.Status.BoundVolumeSnapshotContentName == nil {
		return nil, fmt.Errorf("snapshot %s is not bound to a VolumeSnapshotContent", snapshotName)
	}

	// Get VolumeSnapshotContent to extract CSI snapshot handle
	vsc, err := c.snapClient.SnapshotV1().VolumeSnapshotContents().Get(ctx, *snapshot.Status.BoundVolumeSnapshotContentName, metav1.GetOptions{})
	if err != nil {
		return nil, fmt.Errorf("failed to get VolumeSnapshotContent: %w", err)
	}

	if vsc.Status == nil || vsc.Status.SnapshotHandle == nil {
		return nil, fmt.Errorf("VolumeSnapshotContent has no snapshot handle")
	}

	snapshotHandle := *vsc.Status.SnapshotHandle

	// Call GetMetadataAllocated RPC
	req := &csi.GetMetadataAllocatedRequest{
		SnapshotId:     snapshotHandle,
		StartingOffset: 0,
		MaxResults:     0, // 0 means no limit
	}

	stream, err := c.client.GetMetadataAllocated(ctx, req)
	if err != nil {
		return nil, fmt.Errorf("failed to call GetMetadataAllocated: %w", err)
	}

	// Collect block metadata from stream
	var blockList []blocks.BlockMetadata
	for {
		resp, err := stream.Recv()
		if err == io.EOF {
			break
		}
		if err != nil {
			return nil, fmt.Errorf("error receiving block metadata: %w", err)
		}

		// Convert CSI BlockMetadata to our format
		if resp.BlockMetadata != nil {
			for _, block := range resp.BlockMetadata {
				blockList = append(blockList, blocks.BlockMetadata{
					Offset: block.ByteOffset,
					Size:   block.SizeBytes,
				})
			}
		}
	}

	return blockList, nil
}

// GetDeltaBlocks returns blocks that changed between two snapshots
// This calls the CSI GetMetadataDelta RPC
//
// IMPORTANT: As of kubernetes-csi/external-snapshot-metadata PR #180, the API changed:
//   - The field name changed from base_snapshot_name to base_snapshot_id
//   - baseSnapshotID should now be the CSI snapshot handle (from VolumeSnapshotContent.Status.SnapshotHandle)
//     rather than the VolumeSnapshot name
//   - The CSI handle approach allows computing deltas even after the base snapshot has been deleted
func (c *CBTClient) GetDeltaBlocks(ctx context.Context, baseSnapshotName, targetSnapshotName string) ([]blocks.BlockMetadata, error) {
	if c.client == nil {
		return nil, fmt.Errorf("not connected to CSI driver - call Connect() first")
	}

	// Get base snapshot's CSI handle
	baseSnapshot, err := c.snapClient.SnapshotV1().VolumeSnapshots(c.namespace).Get(ctx, baseSnapshotName, metav1.GetOptions{})
	if err != nil {
		return nil, fmt.Errorf("failed to get base VolumeSnapshot %s: %w", baseSnapshotName, err)
	}

	if baseSnapshot.Status == nil || baseSnapshot.Status.BoundVolumeSnapshotContentName == nil {
		return nil, fmt.Errorf("base snapshot %s is not bound", baseSnapshotName)
	}

	baseVSC, err := c.snapClient.SnapshotV1().VolumeSnapshotContents().Get(ctx, *baseSnapshot.Status.BoundVolumeSnapshotContentName, metav1.GetOptions{})
	if err != nil {
		return nil, fmt.Errorf("failed to get base VolumeSnapshotContent: %w", err)
	}

	if baseVSC.Status == nil || baseVSC.Status.SnapshotHandle == nil {
		return nil, fmt.Errorf("base VolumeSnapshotContent has no snapshot handle")
	}

	baseHandle := *baseVSC.Status.SnapshotHandle

	// Get target snapshot's CSI handle
	targetSnapshot, err := c.snapClient.SnapshotV1().VolumeSnapshots(c.namespace).Get(ctx, targetSnapshotName, metav1.GetOptions{})
	if err != nil {
		return nil, fmt.Errorf("failed to get target VolumeSnapshot %s: %w", targetSnapshotName, err)
	}

	if targetSnapshot.Status == nil || targetSnapshot.Status.BoundVolumeSnapshotContentName == nil {
		return nil, fmt.Errorf("target snapshot %s is not bound", targetSnapshotName)
	}

	targetVSC, err := c.snapClient.SnapshotV1().VolumeSnapshotContents().Get(ctx, *targetSnapshot.Status.BoundVolumeSnapshotContentName, metav1.GetOptions{})
	if err != nil {
		return nil, fmt.Errorf("failed to get target VolumeSnapshotContent: %w", err)
	}

	if targetVSC.Status == nil || targetVSC.Status.SnapshotHandle == nil {
		return nil, fmt.Errorf("target VolumeSnapshotContent has no snapshot handle")
	}

	targetHandle := *targetVSC.Status.SnapshotHandle

	// Call GetMetadataDelta RPC (using CSI handles per PR #180)
	req := &csi.GetMetadataDeltaRequest{
		BaseSnapshotId:   baseHandle,
		TargetSnapshotId: targetHandle,
		StartingOffset:   0,
		MaxResults:       0, // 0 means no limit
	}

	stream, err := c.client.GetMetadataDelta(ctx, req)
	if err != nil {
		return nil, fmt.Errorf("failed to call GetMetadataDelta: %w", err)
	}

	// Collect block metadata from stream
	var blockList []blocks.BlockMetadata
	for {
		resp, err := stream.Recv()
		if err == io.EOF {
			break
		}
		if err != nil {
			return nil, fmt.Errorf("error receiving delta block metadata: %w", err)
		}

		// Convert CSI BlockMetadata to our format
		if resp.BlockMetadata != nil {
			for _, block := range resp.BlockMetadata {
				blockList = append(blockList, blocks.BlockMetadata{
					Offset: block.ByteOffset,
					Size:   block.SizeBytes,
				})
			}
		}
	}

	return blockList, nil
}

// GetSnapshotInfo retrieves detailed information about a VolumeSnapshot
func (c *CBTClient) GetSnapshotInfo(ctx context.Context, snapshotName string) (*snapshotv1.VolumeSnapshot, error) {
	return c.snapClient.SnapshotV1().VolumeSnapshots(c.namespace).Get(ctx, snapshotName, metav1.GetOptions{})
}

// Close closes the gRPC connection
func (c *CBTClient) Close() error {
	if c.conn != nil {
		return c.conn.Close()
	}
	return nil
}
