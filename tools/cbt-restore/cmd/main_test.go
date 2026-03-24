package main

import (
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
