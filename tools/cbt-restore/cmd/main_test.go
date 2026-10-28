package main

import (
	"bytes"
	"crypto/sha256"
	"fmt"
	"os"
	"path/filepath"
	"testing"

	"github.com/kaovilai/k8s-cbt-s3mover-demo/tools/cbt-restore/pkg/blocks"
)

func TestBlockWriteAndVerify(t *testing.T) {
	// Create a temp file to simulate a block device
	tmpDir := t.TempDir()
	devicePath := filepath.Join(tmpDir, "test-device")

	// Create a 1MB file
	f, err := os.Create(devicePath)
	if err != nil {
		t.Fatalf("failed to create temp file: %v", err)
	}
	if err := f.Truncate(1024 * 1024); err != nil {
		t.Fatalf("failed to truncate: %v", err)
	}
	f.Close()

	// Write a block
	writer, err := blocks.NewWriter(devicePath, blocks.DefaultBlockSize)
	if err != nil {
		t.Fatalf("failed to create writer: %v", err)
	}

	testData := []byte("Hello, CBT restore!")
	bd := &blocks.BlockData{
		Offset: 4096,
		Size:   int64(len(testData)),
		Data:   testData,
	}

	if err := writer.WriteBlock(bd); err != nil {
		t.Fatalf("failed to write block: %v", err)
	}
	writer.Close()

	// Read back and verify
	f, err = os.Open(devicePath)
	if err != nil {
		t.Fatalf("failed to open for reading: %v", err)
	}
	defer f.Close()

	buf := make([]byte, len(testData))
	if _, err := f.ReadAt(buf, 4096); err != nil {
		t.Fatalf("failed to read back: %v", err)
	}

	if string(buf) != string(testData) {
		t.Errorf("data mismatch: got %q, want %q", string(buf), string(testData))
	}
}

func TestVerifyChecksum(t *testing.T) {
	data := []byte("test data")
	// SHA256 of "test data"
	expected := "916f0027a575074ce72a331777c3478d6513f786a591bd892da1a577bf2335f9"

	if !blocks.VerifyChecksum(data, expected) {
		t.Error("checksum verification failed for correct data")
	}

	if blocks.VerifyChecksum(data, "wrong-checksum") {
		t.Error("checksum verification should fail for wrong checksum")
	}

	// Empty checksum should pass (no verification)
	if !blocks.VerifyChecksum(data, "") {
		t.Error("empty checksum should pass verification")
	}
}

func TestWriteMultipleBlocks(t *testing.T) {
	tmpDir := t.TempDir()
	devicePath := filepath.Join(tmpDir, "test-device")

	f, err := os.Create(devicePath)
	if err != nil {
		t.Fatalf("failed to create temp file: %v", err)
	}
	if err := f.Truncate(1024 * 1024); err != nil {
		t.Fatalf("failed to truncate: %v", err)
	}
	f.Close()

	writer, err := blocks.NewWriter(devicePath, blocks.DefaultBlockSize)
	if err != nil {
		t.Fatalf("failed to create writer: %v", err)
	}

	blockList := []*blocks.BlockData{
		{Offset: 0, Size: 5, Data: []byte("AAAAA")},
		{Offset: 4096, Size: 5, Data: []byte("BBBBB")},
		{Offset: 8192, Size: 5, Data: []byte("CCCCC")},
	}

	if err := writer.WriteBlocks(blockList); err != nil {
		t.Fatalf("failed to write blocks: %v", err)
	}
	writer.Close()

	// Verify each block
	f, err = os.Open(devicePath)
	if err != nil {
		t.Fatalf("failed to open for reading: %v", err)
	}
	defer f.Close()

	for _, expected := range blockList {
		buf := make([]byte, expected.Size)
		if _, err := f.ReadAt(buf, expected.Offset); err != nil {
			t.Fatalf("failed to read at offset %d: %v", expected.Offset, err)
		}
		if string(buf) != string(expected.Data) {
			t.Errorf("offset %d: got %q, want %q", expected.Offset, string(buf), string(expected.Data))
		}
	}
}

func TestWriteBlockRejectsSizeMismatch(t *testing.T) {
	tmpDir := t.TempDir()
	devicePath := filepath.Join(tmpDir, "test-device")

	f, err := os.Create(devicePath)
	if err != nil {
		t.Fatalf("failed to create temp file: %v", err)
	}
	if err := f.Truncate(4096); err != nil {
		t.Fatalf("failed to truncate: %v", err)
	}
	f.Close()

	writer, err := blocks.NewWriter(devicePath, blocks.DefaultBlockSize)
	if err != nil {
		t.Fatalf("failed to create writer: %v", err)
	}
	defer writer.Close()

	bd := &blocks.BlockData{
		Offset: 0,
		Size:   8,
		Data:   []byte("short"),
	}
	if err := writer.WriteBlock(bd); err == nil {
		t.Fatal("expected size mismatch error, got nil")
	}
}

func TestWriteBlockRejectsNegativeOffset(t *testing.T) {
	tmpDir := t.TempDir()
	devicePath := filepath.Join(tmpDir, "test-device")

	f, err := os.Create(devicePath)
	if err != nil {
		t.Fatalf("failed to create temp file: %v", err)
	}
	if err := f.Truncate(4096); err != nil {
		t.Fatalf("failed to truncate: %v", err)
	}
	f.Close()

	writer, err := blocks.NewWriter(devicePath, blocks.DefaultBlockSize)
	if err != nil {
		t.Fatalf("failed to create writer: %v", err)
	}
	defer writer.Close()

	bd := &blocks.BlockData{
		Offset: -1,
		Size:   5,
		Data:   []byte("AAAAA"),
	}
	if err := writer.WriteBlock(bd); err == nil {
		t.Fatal("expected negative offset error, got nil")
	}
}

func TestWriterSize(t *testing.T) {
	tmpDir := t.TempDir()
	devicePath := filepath.Join(tmpDir, "test-device")

	f, err := os.Create(devicePath)
	if err != nil {
		t.Fatalf("failed to create temp file: %v", err)
	}
	if err := f.Truncate(4096); err != nil {
		t.Fatalf("failed to truncate: %v", err)
	}
	f.Close()

	writer, err := blocks.NewWriter(devicePath, blocks.DefaultBlockSize)
	if err != nil {
		t.Fatalf("failed to create writer: %v", err)
	}
	defer writer.Close()

	size, err := writer.Size()
	if err != nil {
		t.Fatalf("Size failed: %v", err)
	}
	if size != 4096 {
		t.Errorf("size mismatch: got %d, want %d", size, 4096)
	}
}

func TestCheckDeviceSize(t *testing.T) {
	tests := []struct {
		name       string
		deviceSize int64
		volumeSize int64
		wantErr    bool
	}{
		{name: "device smaller than volume", deviceSize: 100, volumeSize: 200, wantErr: true},
		{name: "device equals volume", deviceSize: 200, volumeSize: 200},
		{name: "device larger than volume", deviceSize: 300, volumeSize: 200},
		{name: "unknown volume size", deviceSize: 100, volumeSize: 0},
		{name: "unknown device size", deviceSize: 0, volumeSize: 200},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			err := checkDeviceSize(tt.deviceSize, tt.volumeSize)
			if (err != nil) != tt.wantErr {
				t.Fatalf("checkDeviceSize(%d, %d) error = %v, wantErr %v", tt.deviceSize, tt.volumeSize, err, tt.wantErr)
			}
		})
	}
}

func TestZeroRange(t *testing.T) {
	tmpDir := t.TempDir()
	devicePath := filepath.Join(tmpDir, "test-device")
	if err := os.WriteFile(devicePath, bytes.Repeat([]byte{0xab}, 8192), 0o600); err != nil {
		t.Fatalf("failed to write test device: %v", err)
	}

	writer, err := blocks.NewWriter(devicePath, blocks.DefaultBlockSize)
	if err != nil {
		t.Fatalf("failed to create writer: %v", err)
	}
	if err := writer.Zero(2048, 2048); err != nil {
		t.Fatalf("Zero failed: %v", err)
	}
	if err := writer.Close(); err != nil {
		t.Fatalf("Close failed: %v", err)
	}

	data, err := os.ReadFile(devicePath)
	if err != nil {
		t.Fatalf("failed to read device: %v", err)
	}
	if len(data) != 8192 {
		t.Fatalf("size mismatch: got %d, want 8192", len(data))
	}

	for i, b := range data {
		want := byte(0xab)
		if i >= 2048 && i < 4096 {
			want = 0
		}
		if b != want {
			t.Fatalf("byte %d = 0x%02x, want 0x%02x", i, b, want)
		}
	}
}

func TestVerifyWrittenBlock(t *testing.T) {
	tmpDir := t.TempDir()
	devicePath := filepath.Join(tmpDir, "test-device")

	f, err := os.Create(devicePath)
	if err != nil {
		t.Fatalf("failed to create temp file: %v", err)
	}
	data := []byte("hello, cbt")
	if _, err := f.WriteAt(data, 0); err != nil {
		t.Fatalf("failed to write data: %v", err)
	}
	if err := f.Truncate(4096); err != nil {
		t.Fatalf("failed to truncate: %v", err)
	}
	f.Close()

	writer, err := blocks.NewWriter(devicePath, blocks.DefaultBlockSize)
	if err != nil {
		t.Fatalf("failed to create writer: %v", err)
	}
	defer writer.Close()
	if err := writer.EnableReadBack(); err != nil {
		t.Fatalf("failed to enable read-back: %v", err)
	}

	sum := sha256.Sum256(data)
	expected := fmt.Sprintf("%x", sum)
	if err := verifyWrittenBlock(writer, 0, int64(len(data)), expected); err != nil {
		t.Fatalf("verifyWrittenBlock failed for matching data: %v", err)
	}
	if err := verifyWrittenBlock(writer, 0, int64(len(data)), "wrong-checksum"); err == nil {
		t.Fatal("expected checksum mismatch error, got nil")
	}
}
