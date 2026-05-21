package blocks

import (
	"crypto/sha256"
	"fmt"
	"os"
	"path/filepath"
	"testing"
)

func makeTestDevice(t *testing.T, size int64) string {
	t.Helper()
	tmpDir := t.TempDir()
	path := filepath.Join(tmpDir, "test-device")
	f, err := os.Create(path)
	if err != nil {
		t.Fatalf("failed to create test device: %v", err)
	}
	if err := f.Truncate(size); err != nil {
		t.Fatalf("failed to truncate: %v", err)
	}
	f.Close()
	return path
}

func TestNewReader(t *testing.T) {
	path := makeTestDevice(t, 4096)
	r, err := NewReader(path, 0)
	if err != nil {
		t.Fatalf("NewReader failed: %v", err)
	}
	defer r.Close()

	if r.blockSize != DefaultBlockSize {
		t.Errorf("expected blockSize %d, got %d", DefaultBlockSize, r.blockSize)
	}
}

func TestNewReader_NonExistentFile(t *testing.T) {
	_, err := NewReader("/nonexistent/path/device", DefaultBlockSize)
	if err == nil {
		t.Error("expected error for non-existent device, got nil")
	}
}

func TestReadBlock(t *testing.T) {
	path := makeTestDevice(t, 4096*4)

	// Write known data at offset 4096
	f, _ := os.OpenFile(path, os.O_WRONLY, 0)
	testData := []byte("Hello, CBT backup!")
	f.WriteAt(testData, 4096)
	f.Close()

	r, err := NewReader(path, DefaultBlockSize)
	if err != nil {
		t.Fatalf("NewReader failed: %v", err)
	}
	defer r.Close()

	bd, err := r.ReadBlock(4096, int64(len(testData)))
	if err != nil {
		t.Fatalf("ReadBlock failed: %v", err)
	}

	if string(bd.Data) != string(testData) {
		t.Errorf("data mismatch: got %q, want %q", bd.Data, testData)
	}
	if bd.Offset != 4096 {
		t.Errorf("offset mismatch: got %d, want %d", bd.Offset, 4096)
	}
	if bd.Size != int64(len(testData)) {
		t.Errorf("size mismatch: got %d, want %d", bd.Size, len(testData))
	}

	// Verify checksum
	hash := sha256.Sum256(testData)
	expectedChecksum := fmt.Sprintf("%x", hash)
	if bd.Checksum != expectedChecksum {
		t.Errorf("checksum mismatch: got %s, want %s", bd.Checksum, expectedChecksum)
	}
}

func TestGetDeviceSize(t *testing.T) {
	const deviceSize = 8192
	path := makeTestDevice(t, deviceSize)

	r, err := NewReader(path, DefaultBlockSize)
	if err != nil {
		t.Fatalf("NewReader failed: %v", err)
	}
	defer r.Close()

	size, err := r.GetDeviceSize()
	if err != nil {
		t.Fatalf("GetDeviceSize failed: %v", err)
	}
	if size != deviceSize {
		t.Errorf("size mismatch: got %d, want %d", size, deviceSize)
	}
}

func TestReadBlocks(t *testing.T) {
	path := makeTestDevice(t, 4096*4)

	// Write data at two offsets
	f, _ := os.OpenFile(path, os.O_WRONLY, 0)
	f.WriteAt([]byte("AAAAA"), 0)
	f.WriteAt([]byte("BBBBB"), 4096)
	f.Close()

	r, err := NewReader(path, DefaultBlockSize)
	if err != nil {
		t.Fatalf("NewReader failed: %v", err)
	}
	defer r.Close()

	metadata := []BlockMetadata{
		{Offset: 0, Size: 5},
		{Offset: 4096, Size: 5},
	}

	results, err := r.ReadBlocks(metadata)
	if err != nil {
		t.Fatalf("ReadBlocks failed: %v", err)
	}

	if len(results) != 2 {
		t.Fatalf("expected 2 results, got %d", len(results))
	}
	if string(results[0].Data) != "AAAAA" {
		t.Errorf("block[0] data mismatch: got %q", results[0].Data)
	}
	if string(results[1].Data) != "BBBBB" {
		t.Errorf("block[1] data mismatch: got %q", results[1].Data)
	}
}

func TestScanNonZeroBlocks(t *testing.T) {
	path := makeTestDevice(t, 4096*4)

	// Write data at block 1 only (leave block 0 and blocks 2-3 as zero)
	f, _ := os.OpenFile(path, os.O_WRONLY, 0)
	f.WriteAt([]byte("nonzero"), 4096)
	f.Close()

	blocks, err := ScanNonZeroBlocks(path, 4096)
	if err != nil {
		t.Fatalf("ScanNonZeroBlocks failed: %v", err)
	}

	if len(blocks) != 1 {
		t.Fatalf("expected 1 non-zero block, got %d", len(blocks))
	}
	if blocks[0].Offset != 4096 {
		t.Errorf("expected non-zero block at offset 4096, got %d", blocks[0].Offset)
	}
}

func TestScanNonZeroBlocks_AllZero(t *testing.T) {
	path := makeTestDevice(t, 4096*2)

	blocks, err := ScanNonZeroBlocks(path, 4096)
	if err != nil {
		t.Fatalf("ScanNonZeroBlocks failed: %v", err)
	}

	if len(blocks) != 0 {
		t.Errorf("expected 0 non-zero blocks for zeroed device, got %d", len(blocks))
	}
}

func TestScanNonZeroBlocks_DefaultBlockSize(t *testing.T) {
	path := makeTestDevice(t, DefaultBlockSize*2)

	// Write data at second block
	f, _ := os.OpenFile(path, os.O_WRONLY, 0)
	f.WriteAt([]byte("data"), DefaultBlockSize)
	f.Close()

	blocks, err := ScanNonZeroBlocks(path, 0) // 0 should use DefaultBlockSize
	if err != nil {
		t.Fatalf("ScanNonZeroBlocks failed: %v", err)
	}

	if len(blocks) != 1 {
		t.Fatalf("expected 1 non-zero block, got %d", len(blocks))
	}
	if blocks[0].Offset != DefaultBlockSize {
		t.Errorf("expected non-zero block at offset %d, got %d", DefaultBlockSize, blocks[0].Offset)
	}
}
