package snapshot

import (
	"context"
	"fmt"
	"time"

	snapshotv1 "github.com/kubernetes-csi/external-snapshotter/client/v8/apis/volumesnapshot/v1"
	snapclientset "github.com/kubernetes-csi/external-snapshotter/client/v8/clientset/versioned"
	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/util/wait"
	"k8s.io/client-go/kubernetes"
	"k8s.io/client-go/rest"
	"k8s.io/client-go/tools/clientcmd"
)

// Manager handles Kubernetes VolumeSnapshot operations
type Manager struct {
	k8sClient      kubernetes.Interface
	snapshotClient snapclientset.Interface
	namespace      string
}

// NewManager creates a new snapshot manager
func NewManager(namespace string, kubeconfig string) (*Manager, error) {
	var config *rest.Config
	var err error

	if kubeconfig != "" {
		config, err = clientcmd.BuildConfigFromFlags("", kubeconfig)
	} else {
		config, err = rest.InClusterConfig()
	}
	if err != nil {
		return nil, fmt.Errorf("failed to get kubernetes config: %w", err)
	}

	k8sClient, err := kubernetes.NewForConfig(config)
	if err != nil {
		return nil, fmt.Errorf("failed to create kubernetes client: %w", err)
	}

	snapshotClient, err := snapclientset.NewForConfig(config)
	if err != nil {
		return nil, fmt.Errorf("failed to create snapshot client: %w", err)
	}

	return &Manager{
		k8sClient:      k8sClient,
		snapshotClient: snapshotClient,
		namespace:      namespace,
	}, nil
}

// CreateSnapshot creates a VolumeSnapshot for the given PVC
func (m *Manager) CreateSnapshot(ctx context.Context, pvcName, snapshotName, snapshotClass string) (*snapshotv1.VolumeSnapshot, error) {
	// Verify PVC exists and is block mode
	pvc, err := m.k8sClient.CoreV1().PersistentVolumeClaims(m.namespace).Get(ctx, pvcName, metav1.GetOptions{})
	if err != nil {
		return nil, fmt.Errorf("failed to get PVC %s: %w", pvcName, err)
	}

	if pvc.Spec.VolumeMode == nil || *pvc.Spec.VolumeMode != corev1.PersistentVolumeBlock {
		return nil, fmt.Errorf("PVC %s is not in Block mode (required for CBT)", pvcName)
	}

	// Generate snapshot name if not provided
	if snapshotName == "" {
		snapshotName = fmt.Sprintf("%s-snapshot-%d", pvcName, time.Now().Unix())
	}

	snapshot := &snapshotv1.VolumeSnapshot{
		ObjectMeta: metav1.ObjectMeta{
			Name:      snapshotName,
			Namespace: m.namespace,
		},
		Spec: snapshotv1.VolumeSnapshotSpec{
			VolumeSnapshotClassName: &snapshotClass,
			Source: snapshotv1.VolumeSnapshotSource{
				PersistentVolumeClaimName: &pvcName,
			},
		},
	}

	created, err := m.snapshotClient.SnapshotV1().VolumeSnapshots(m.namespace).Create(ctx, snapshot, metav1.CreateOptions{})
	if err != nil {
		return nil, fmt.Errorf("failed to create snapshot: %w", err)
	}

	fmt.Printf("Created VolumeSnapshot: %s\n", created.Name)
	return created, nil
}

// WaitForSnapshotReady waits for a snapshot to become ready
func (m *Manager) WaitForSnapshotReady(ctx context.Context, snapshotName string, timeout time.Duration) (*snapshotv1.VolumeSnapshot, error) {
	fmt.Printf("Waiting for snapshot %s to be ready...\n", snapshotName)

	var snapshot *snapshotv1.VolumeSnapshot
	err := wait.PollUntilContextTimeout(ctx, 5*time.Second, timeout, true, func(ctx context.Context) (bool, error) {
		var err error
		snapshot, err = m.snapshotClient.SnapshotV1().VolumeSnapshots(m.namespace).Get(ctx, snapshotName, metav1.GetOptions{})
		if err != nil {
			return false, err
		}

		if snapshot.Status == nil {
			return false, nil
		}

		if snapshot.Status.ReadyToUse != nil && *snapshot.Status.ReadyToUse {
			return true, nil
		}

		if snapshot.Status.Error != nil {
			return false, fmt.Errorf("snapshot error: %s", *snapshot.Status.Error.Message)
		}

		return false, nil
	})

	if err != nil {
		return nil, fmt.Errorf("snapshot did not become ready: %w", err)
	}

	fmt.Printf("✓ Snapshot %s is ready (size: %s)\n", snapshotName, snapshot.Status.RestoreSize.String())
	return snapshot, nil
}

// GetSnapshot retrieves a snapshot by name
func (m *Manager) GetSnapshot(ctx context.Context, snapshotName string) (*snapshotv1.VolumeSnapshot, error) {
	return m.snapshotClient.SnapshotV1().VolumeSnapshots(m.namespace).Get(ctx, snapshotName, metav1.GetOptions{})
}

// ListSnapshots lists all snapshots in the namespace
func (m *Manager) ListSnapshots(ctx context.Context) (*snapshotv1.VolumeSnapshotList, error) {
	return m.snapshotClient.SnapshotV1().VolumeSnapshots(m.namespace).List(ctx, metav1.ListOptions{})
}

// GetSnapshotContent gets the VolumeSnapshotContent for a snapshot
func (m *Manager) GetSnapshotContent(ctx context.Context, snapshot *snapshotv1.VolumeSnapshot) (*snapshotv1.VolumeSnapshotContent, error) {
	if snapshot.Status == nil || snapshot.Status.BoundVolumeSnapshotContentName == nil {
		return nil, fmt.Errorf("snapshot %s is not bound to content", snapshot.Name)
	}

	contentName := *snapshot.Status.BoundVolumeSnapshotContentName
	return m.snapshotClient.SnapshotV1().VolumeSnapshotContents().Get(ctx, contentName, metav1.GetOptions{})
}

// GetPVC gets the PVC for a snapshot
func (m *Manager) GetPVC(ctx context.Context, pvcName string) (*corev1.PersistentVolumeClaim, error) {
	return m.k8sClient.CoreV1().PersistentVolumeClaims(m.namespace).Get(ctx, pvcName, metav1.GetOptions{})
}

// DeleteSnapshot deletes a snapshot
func (m *Manager) DeleteSnapshot(ctx context.Context, snapshotName string) error {
	return m.snapshotClient.SnapshotV1().VolumeSnapshots(m.namespace).Delete(ctx, snapshotName, metav1.DeleteOptions{})
}
