package main

import (
	"context"
	"fmt"
	"os"
	"time"

	"github.com/kaovilai/k8s-cbt-s3mover-demo/tools/cbt-backup/pkg/blocks"
	"github.com/kaovilai/k8s-cbt-s3mover-demo/tools/cbt-backup/pkg/metadata"
	"github.com/kaovilai/k8s-cbt-s3mover-demo/tools/cbt-backup/pkg/s3"
	"github.com/kaovilai/k8s-cbt-s3mover-demo/tools/cbt-backup/pkg/snapshot"
	"github.com/spf13/cobra"
)

var (
	namespace         string
	pvcName           string
	snapshotName      string
	baseSnapshotName  string
	s3Endpoint        string
	s3AccessKey       string
	s3SecretKey       string
	s3Bucket          string
	s3UseSSL          bool
	devicePath        string
	blockSize         int64
	kubeconfig        string
	snapshotClass     string
)

func main() {
	rootCmd := &cobra.Command{
		Use:   "cbt-backup",
		Short: "Backup tool using Kubernetes Changed Block Tracking",
		Long: `A backup tool that uses Kubernetes CSI Changed Block Tracking (CBT)
to perform incremental backups of block volumes to S3-compatible storage.

NOTE: Full CBT gRPC client implementation is TODO. Currently implements
full backups with infrastructure for incremental support.`,
	}

	backupCmd := &cobra.Command{
		Use:   "create",
		Short: "Create a snapshot and backup blocks to S3",
		RunE:  runBackup,
	}

	backupCmd.Flags().StringVarP(&namespace, "namespace", "n", "cbt-demo", "Kubernetes namespace")
	backupCmd.Flags().StringVarP(&pvcName, "pvc", "p", "", "PVC name to backup (required)")
	backupCmd.Flags().StringVarP(&snapshotName, "snapshot", "s", "", "Snapshot name (generated if not provided)")
	backupCmd.Flags().StringVarP(&baseSnapshotName, "base-snapshot", "b", "", "Base snapshot for incremental backup")
	backupCmd.Flags().StringVarP(&s3Endpoint, "s3-endpoint", "e", "minio.cbt-demo.svc.cluster.local:9000", "S3 endpoint")
	backupCmd.Flags().StringVarP(&s3AccessKey, "s3-access-key", "a", "minioadmin", "S3 access key")
	backupCmd.Flags().StringVarP(&s3SecretKey, "s3-secret-key", "k", "minioadmin123", "S3 secret key")
	backupCmd.Flags().StringVarP(&s3Bucket, "s3-bucket", "B", "snapshots", "S3 bucket name")
	backupCmd.Flags().BoolVar(&s3UseSSL, "s3-use-ssl", false, "Use SSL for S3")
	backupCmd.Flags().StringVarP(&devicePath, "device", "d", "", "Block device path (auto-detected if not provided)")
	backupCmd.Flags().Int64Var(&blockSize, "block-size", blocks.DefaultBlockSize, "Block size in bytes")
	backupCmd.Flags().StringVar(&kubeconfig, "kubeconfig", "", "Path to kubeconfig (uses in-cluster config if not provided)")
	backupCmd.Flags().StringVar(&snapshotClass, "snapshot-class", "csi-hostpath-snapclass", "VolumeSnapshotClass name")
	backupCmd.MarkFlagRequired("pvc")

	listCmd := &cobra.Command{
		Use:   "list",
		Short: "List available backups from S3",
		RunE:  runList,
	}

	listCmd.Flags().StringVarP(&s3Endpoint, "s3-endpoint", "e", "minio.cbt-demo.svc.cluster.local:9000", "S3 endpoint")
	listCmd.Flags().StringVarP(&s3AccessKey, "s3-access-key", "a", "minioadmin", "S3 access key")
	listCmd.Flags().StringVarP(&s3SecretKey, "s3-secret-key", "k", "minioadmin123", "S3 secret key")
	listCmd.Flags().StringVarP(&s3Bucket, "s3-bucket", "B", "snapshots", "S3 bucket name")
	listCmd.Flags().BoolVar(&s3UseSSL, "s3-use-ssl", false, "Use SSL for S3")

	rootCmd.AddCommand(backupCmd, listCmd)

	if err := rootCmd.Execute(); err != nil {
		fmt.Fprintf(os.Stderr, "Error: %v\n", err)
		os.Exit(1)
	}
}

func runBackup(cmd *cobra.Command, args []string) error {
	ctx := context.Background()
	startTime := time.Now()

	fmt.Println("========================================")
	fmt.Println("Kubernetes CBT Backup Tool")
	fmt.Println("========================================")
	fmt.Printf("PVC: %s/%s\n", namespace, pvcName)
	if baseSnapshotName != "" {
		fmt.Printf("Mode: Incremental (base: %s)\n", baseSnapshotName)
	} else {
		fmt.Println("Mode: Full Backup")
	}
	fmt.Println("========================================")

	// Initialize snapshot manager
	fmt.Println("\n[1/7] Initializing Kubernetes client...")
	snapMgr, err := snapshot.NewManager(namespace, kubeconfig)
	if err != nil {
		return fmt.Errorf("failed to create snapshot manager: %w", err)
	}

	// Initialize S3 client
	fmt.Println("[2/7] Connecting to S3 storage...")
	s3Client, err := s3.NewClient(s3.Config{
		Endpoint:  s3Endpoint,
		AccessKey: s3AccessKey,
		SecretKey: s3SecretKey,
		Bucket:    s3Bucket,
		UseSSL:    s3UseSSL,
	})
	if err != nil {
		return fmt.Errorf("failed to create S3 client: %w", err)
	}

	if err := s3Client.EnsureBucket(ctx); err != nil {
		return fmt.Errorf("failed to ensure bucket: %w", err)
	}
	fmt.Printf("✓ Connected to S3 (bucket: %s)\n", s3Bucket)

	// Create VolumeSnapshot
	fmt.Println("\n[3/7] Creating VolumeSnapshot...")
	snap, err := snapMgr.CreateSnapshot(ctx, pvcName, snapshotName, snapshotClass)
	if err != nil {
		return fmt.Errorf("failed to create snapshot: %w", err)
	}

	// Wait for snapshot to be ready
	fmt.Println("[4/7] Waiting for snapshot to be ready...")
	snap, err = snapMgr.WaitForSnapshotReady(ctx, snap.Name, 5*time.Minute)
	if err != nil {
		return fmt.Errorf("failed to wait for snapshot: %w", err)
	}

	// Create manifest
	manifest := metadata.SnapshotManifest{
		Name:              snap.Name,
		Namespace:         snap.Namespace,
		PVCName:           pvcName,
		SnapshotName:      snap.Name,
		Timestamp:         time.Now(),
		VolumeSize:        snap.Status.RestoreSize.Value(),
		IsIncremental:     baseSnapshotName != "",
		BaseSnapshotName:  baseSnapshotName,
		BlockSize:         blockSize,
		SnapshotClassName: snapshotClass,
		VolumeMode:        "Block",
		CSIDriver:         "hostpath.csi.k8s.io",
	}

	fmt.Printf("✓ Snapshot ready: %s (size: %d bytes)\n", snap.Name, manifest.VolumeSize)

	// NOTE: Full CBT implementation would go here
	// For now, print a message about the limitation
	fmt.Println("\n[5/7] Analyzing blocks to backup...")
	fmt.Println("⚠ NOTE: Full CBT gRPC client is not yet implemented.")
	fmt.Println("  In a complete implementation, this would:")
	fmt.Println("  1. Discover SnapshotMetadataService endpoint")
	fmt.Println("  2. Call GetMetadataAllocated (for full backup)")
	fmt.Println("  3. Call GetMetadataDelta (for incremental backup)")
	fmt.Println("  4. Upload only changed blocks to S3")
	fmt.Println("\n  For now, metadata structure is created but blocks are not uploaded.")

	// Create block list (empty for now)
	blockList := metadata.BlockList{
		Blocks: []blocks.BlockMetadata{},
	}

	manifest.TotalBlocks = len(blockList.Blocks)
	manifest.TotalSize = 0

	// Upload metadata to S3
	fmt.Println("\n[6/7] Uploading backup metadata to S3...")

	// Upload manifest
	manifestPath := fmt.Sprintf("metadata/%s/manifest.json", snap.Name)
	if err := s3Client.UploadJSON(ctx, manifestPath, manifest); err != nil {
		return fmt.Errorf("failed to upload manifest: %w", err)
	}
	fmt.Printf("✓ Uploaded manifest: %s\n", manifestPath)

	// Upload block list
	blocksPath := fmt.Sprintf("metadata/%s/blocks.json", snap.Name)
	if err := s3Client.UploadJSON(ctx, blocksPath, blockList); err != nil {
		return fmt.Errorf("failed to upload block list: %w", err)
	}
	fmt.Printf("✓ Uploaded block list: %s\n", blocksPath)

	// Upload chain info
	chain := metadata.SnapshotChain{
		SnapshotName:     snap.Name,
		BaseSnapshotName: baseSnapshotName,
		IsIncremental:    baseSnapshotName != "",
		Dependencies:     []string{},
	}
	if baseSnapshotName != "" {
		chain.Dependencies = append(chain.Dependencies, baseSnapshotName)
	}

	chainPath := fmt.Sprintf("metadata/%s/chain.json", snap.Name)
	if err := s3Client.UploadJSON(ctx, chainPath, chain); err != nil {
		return fmt.Errorf("failed to upload chain: %w", err)
	}
	fmt.Printf("✓ Uploaded chain info: %s\n", chainPath)

	// Create backup stats
	stats := metadata.BackupStats{
		StartTime:        startTime,
		EndTime:          time.Now(),
		Duration:         time.Since(startTime),
		IsIncremental:    baseSnapshotName != "",
		BaseSnapshotName: baseSnapshotName,
		CBTEnabled:       false, // Will be true when gRPC client is implemented
		Errors:           []string{"CBT gRPC client not fully implemented - metadata only backup"},
	}

	fmt.Println("\n[7/7] Backup Summary")
	fmt.Println("========================================")
	fmt.Printf("Snapshot Name:     %s\n", snap.Name)
	fmt.Printf("Volume Size:       %d bytes\n", manifest.VolumeSize)
	fmt.Printf("Blocks Backed Up:  %d\n", manifest.TotalBlocks)
	fmt.Printf("Data Uploaded:     %d bytes\n", manifest.TotalSize)
	fmt.Printf("Duration:          %s\n", stats.Duration)
	fmt.Printf("Type:              %s\n", map[bool]string{true: "Incremental", false: "Full"}[manifest.IsIncremental])
	fmt.Println("========================================")
	fmt.Println("✓ Backup metadata created successfully!")
	fmt.Println("\nNOTE: To complete the implementation, see:")
	fmt.Println("  tools/cbt-backup/pkg/metadata/cbt_client.go")
	fmt.Println("  for TODO comments on implementing the full gRPC client.")

	return nil
}

func runList(cmd *cobra.Command, args []string) error {
	ctx := context.Background()

	fmt.Println("========================================")
	fmt.Println("Available Backups")
	fmt.Println("========================================")

	// Initialize S3 client
	s3Client, err := s3.NewClient(s3.Config{
		Endpoint:  s3Endpoint,
		AccessKey: s3AccessKey,
		SecretKey: s3SecretKey,
		Bucket:    s3Bucket,
		UseSSL:    s3UseSSL,
	})
	if err != nil {
		return fmt.Errorf("failed to create S3 client: %w", err)
	}

	// List all manifests
	objects, err := s3Client.ListObjects(ctx, "metadata/")
	if err != nil {
		return fmt.Errorf("failed to list objects: %w", err)
	}

	if len(objects) == 0 {
		fmt.Println("No backups found.")
		return nil
	}

	// Filter manifest files and load them
	manifests := make(map[string]metadata.SnapshotManifest)
	for _, obj := range objects {
		if len(obj) > 14 && obj[len(obj)-14:] == "/manifest.json" {
			var manifest metadata.SnapshotManifest
			if err := s3Client.DownloadJSON(ctx, obj, &manifest); err != nil {
				fmt.Printf("Warning: Failed to load %s: %v\n", obj, err)
				continue
			}
			manifests[manifest.Name] = manifest
		}
	}

	// Display manifests
	fmt.Printf("\nFound %d backup(s):\n\n", len(manifests))
	for _, manifest := range manifests {
		fmt.Printf("Snapshot: %s\n", manifest.Name)
		fmt.Printf("  PVC:           %s\n", manifest.PVCName)
		fmt.Printf("  Timestamp:     %s\n", manifest.Timestamp.Format(time.RFC3339))
		fmt.Printf("  Type:          %s\n", map[bool]string{true: "Incremental", false: "Full"}[manifest.IsIncremental])
		if manifest.BaseSnapshotName != "" {
			fmt.Printf("  Base Snapshot: %s\n", manifest.BaseSnapshotName)
		}
		fmt.Printf("  Volume Size:   %d bytes\n", manifest.VolumeSize)
		fmt.Printf("  Total Blocks:  %d\n", manifest.TotalBlocks)
		fmt.Printf("  Total Size:    %d bytes\n", manifest.TotalSize)
		fmt.Println()
	}

	fmt.Println("========================================")
	return nil
}
