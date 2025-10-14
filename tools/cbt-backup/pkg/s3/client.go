package s3

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"

	"github.com/minio/minio-go/v7"
	"github.com/minio/minio-go/v7/pkg/credentials"
)

// Client wraps MinIO/S3 operations
type Client struct {
	client     *minio.Client
	bucketName string
}

// Config holds S3 connection configuration
type Config struct {
	Endpoint  string
	AccessKey string
	SecretKey string
	Bucket    string
	UseSSL    bool
}

// NewClient creates a new S3 client
func NewClient(cfg Config) (*Client, error) {
	minioClient, err := minio.New(cfg.Endpoint, &minio.Options{
		Creds:  credentials.NewStaticV4(cfg.AccessKey, cfg.SecretKey, ""),
		Secure: cfg.UseSSL,
	})
	if err != nil {
		return nil, fmt.Errorf("failed to create MinIO client: %w", err)
	}

	return &Client{
		client:     minioClient,
		bucketName: cfg.Bucket,
	}, nil
}

// EnsureBucket ensures the bucket exists
func (c *Client) EnsureBucket(ctx context.Context) error {
	exists, err := c.client.BucketExists(ctx, c.bucketName)
	if err != nil {
		return fmt.Errorf("failed to check bucket: %w", err)
	}

	if !exists {
		fmt.Printf("Creating bucket: %s\n", c.bucketName)
		err = c.client.MakeBucket(ctx, c.bucketName, minio.MakeBucketOptions{})
		if err != nil {
			return fmt.Errorf("failed to create bucket: %w", err)
		}
	}

	return nil
}

// UploadBlock uploads a block of data
func (c *Client) UploadBlock(ctx context.Context, objectPath string, data []byte) error {
	reader := bytes.NewReader(data)
	_, err := c.client.PutObject(ctx, c.bucketName, objectPath, reader, int64(len(data)), minio.PutObjectOptions{
		ContentType: "application/octet-stream",
	})
	if err != nil {
		return fmt.Errorf("failed to upload block %s: %w", objectPath, err)
	}

	return nil
}

// UploadJSON uploads JSON data
func (c *Client) UploadJSON(ctx context.Context, objectPath string, data interface{}) error {
	jsonData, err := json.MarshalIndent(data, "", "  ")
	if err != nil {
		return fmt.Errorf("failed to marshal JSON: %w", err)
	}

	reader := bytes.NewReader(jsonData)
	_, err = c.client.PutObject(ctx, c.bucketName, objectPath, reader, int64(len(jsonData)), minio.PutObjectOptions{
		ContentType: "application/json",
	})
	if err != nil {
		return fmt.Errorf("failed to upload JSON %s: %w", objectPath, err)
	}

	return nil
}

// DownloadObject downloads an object
func (c *Client) DownloadObject(ctx context.Context, objectPath string) ([]byte, error) {
	obj, err := c.client.GetObject(ctx, c.bucketName, objectPath, minio.GetObjectOptions{})
	if err != nil {
		return nil, fmt.Errorf("failed to get object %s: %w", objectPath, err)
	}
	defer obj.Close()

	data, err := io.ReadAll(obj)
	if err != nil {
		return nil, fmt.Errorf("failed to read object %s: %w", objectPath, err)
	}

	return data, nil
}

// DownloadJSON downloads and unmarshals JSON data
func (c *Client) DownloadJSON(ctx context.Context, objectPath string, target interface{}) error {
	data, err := c.DownloadObject(ctx, objectPath)
	if err != nil {
		return err
	}

	if err := json.Unmarshal(data, target); err != nil {
		return fmt.Errorf("failed to unmarshal JSON from %s: %w", objectPath, err)
	}

	return nil
}

// ListObjects lists objects with a given prefix
func (c *Client) ListObjects(ctx context.Context, prefix string) ([]string, error) {
	var objects []string

	for object := range c.client.ListObjects(ctx, c.bucketName, minio.ListObjectsOptions{
		Prefix:    prefix,
		Recursive: true,
	}) {
		if object.Err != nil {
			return nil, fmt.Errorf("error listing objects: %w", object.Err)
		}
		objects = append(objects, object.Key)
	}

	return objects, nil
}

// ObjectExists checks if an object exists
func (c *Client) ObjectExists(ctx context.Context, objectPath string) (bool, error) {
	_, err := c.client.StatObject(ctx, c.bucketName, objectPath, minio.StatObjectOptions{})
	if err != nil {
		if minio.ToErrorResponse(err).Code == "NoSuchKey" {
			return false, nil
		}
		return false, fmt.Errorf("failed to stat object %s: %w", objectPath, err)
	}

	return true, nil
}

// GetObjectSize gets the size of an object
func (c *Client) GetObjectSize(ctx context.Context, objectPath string) (int64, error) {
	stat, err := c.client.StatObject(ctx, c.bucketName, objectPath, minio.StatObjectOptions{})
	if err != nil {
		return 0, fmt.Errorf("failed to stat object %s: %w", objectPath, err)
	}

	return stat.Size, nil
}

// DeleteObject deletes an object
func (c *Client) DeleteObject(ctx context.Context, objectPath string) error {
	err := c.client.RemoveObject(ctx, c.bucketName, objectPath, minio.RemoveObjectOptions{})
	if err != nil {
		return fmt.Errorf("failed to delete object %s: %w", objectPath, err)
	}

	return nil
}
