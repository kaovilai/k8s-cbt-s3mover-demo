module github.com/kaovilai/k8s-cbt-s3mover-demo/tools/cbt-backup

go 1.22

require (
	github.com/container-storage-interface/spec v1.11.0
	github.com/kubernetes-csi/external-snapshotter/client/v8 v8.2.0
	github.com/minio/minio-go/v7 v7.0.82
	github.com/spf13/cobra v1.8.1
	google.golang.org/grpc v1.67.1
	k8s.io/api v0.31.3
	k8s.io/apimachinery v0.31.3
	k8s.io/client-go v0.31.3
)
