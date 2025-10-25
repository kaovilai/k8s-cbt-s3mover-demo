package metadata

import (
	"context"
	"fmt"
	"io"

	csi "github.com/container-storage-interface/spec/lib/go/csi"
	"github.com/kaovilai/k8s-cbt-s3mover-demo/tools/cbt-backup/pkg/blocks"
	snapshotv1 "github.com/kubernetes-csi/external-snapshotter/client/v8/apis/volumesnapshot/v1"
	snapclientset "github.com/kubernetes-csi/external-snapshotter/client/v8/clientset/versioned"
	"google.golang.org/grpc"
	"google.golang.org/grpc/credentials/insecure"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/client-go/rest"
	"k8s.io/client-go/tools/clientcmd"
)

// CBTClient interfaces with the CSI SnapshotMetadata service
type CBTClient struct {
	conn          *grpc.ClientConn
	client        csi.SnapshotMetadataClient
	snapClient    *snapclientset.Clientset
	namespace     string
	socketAddress string
}

// NewCBTClient creates a new CBT client
// This implementation:
// 1. Creates a Kubernetes client for snapshot API
// 2. Discovers the SnapshotMetadataService endpoint
// 3. Establishes gRPC connection to the CSI driver
func NewCBTClient(namespace string, kubeconfig string) (*CBTClient, error) {
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

	client := &CBTClient{
		snapClient: snapClient,
		namespace:  namespace,
	}

	// Note: In a production implementation, we would discover the
	// SnapshotMetadataService endpoint from the Kubernetes API.
	// However, the SnapshotMetadataService CRD is still in alpha
	// and may not be available in all clusters.
	//
	// For this demo, we'll use a well-known socket path that matches
	// the CSI hostpath driver deployment.
	client.socketAddress = "unix:///csi/csi.sock"

	return client, nil
}

// Connect establishes the gRPC connection to the CSI driver
func (c *CBTClient) Connect(ctx context.Context) error {
	if c.conn != nil {
		return nil // Already connected
	}

	// Establish gRPC connection
	conn, err := grpc.DialContext(
		ctx,
		c.socketAddress,
		grpc.WithTransportCredentials(insecure.NewCredentials()),
		grpc.WithBlock(),
	)
	if err != nil {
		return fmt.Errorf("failed to connect to CSI driver at %s: %w", c.socketAddress, err)
	}

	c.conn = conn
	c.client = csi.NewSnapshotMetadataClient(conn)

	return nil
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
