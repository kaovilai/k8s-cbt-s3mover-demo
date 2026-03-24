package blocks

import (
	"crypto/sha256"
	"fmt"
	"io"
	"os"
)

const (
	// DefaultBlockSize is the default block size (1MB)
	DefaultBlockSize = 1024 * 1024
)

// BlockMetadata describes a block's location
type BlockMetadata struct {
	Offset int64 `json:"offset"`
	Size   int64 `json:"size"`
}

// BlockData represents a block of data
type BlockData struct {
	Offset   int64  `json:"offset"`
	Size     int64  `json:"size"`
	Checksum string `json:"checksum"`
	Data     []byte `json:"-"`
}

// Writer writes blocks to a device
type Writer struct {
	device    *os.File
	blockSize int64
}

// NewWriter creates a new block writer
func NewWriter(devicePath string, blockSize int64) (*Writer, error) {
	if blockSize <= 0 {
		blockSize = DefaultBlockSize
	}

	device, err := os.OpenFile(devicePath, os.O_WRONLY, 0)
	if err != nil {
		return nil, fmt.Errorf("failed to open device %s for writing: %w", devicePath, err)
	}

	return &Writer{
		device:    device,
		blockSize: blockSize,
	}, nil
}

// Close closes the block writer
func (w *Writer) Close() error {
	if w.device != nil {
		if err := w.device.Sync(); err != nil {
			return fmt.Errorf("failed to sync device: %w", err)
		}
		return w.device.Close()
	}
	return nil
}

// WriteBlock writes a block at the given offset
func (w *Writer) WriteBlock(block *BlockData) error {
	_, err := w.device.Seek(block.Offset, io.SeekStart)
	if err != nil {
		return fmt.Errorf("failed to seek to offset %d: %w", block.Offset, err)
	}

	n, err := w.device.Write(block.Data)
	if err != nil {
		return fmt.Errorf("failed to write block at offset %d: %w", block.Offset, err)
	}

	if int64(n) != block.Size {
		return fmt.Errorf("partial write: wrote %d bytes, expected %d", n, block.Size)
	}

	return nil
}

// WriteBlocks writes multiple blocks and syncs
func (w *Writer) WriteBlocks(blockList []*BlockData) error {
	for _, block := range blockList {
		if err := w.WriteBlock(block); err != nil {
			return err
		}
	}
	return w.device.Sync()
}

// VerifyChecksum computes SHA256 of data and compares to expected checksum
func VerifyChecksum(data []byte, expected string) bool {
	if expected == "" {
		return true
	}
	hash := sha256.Sum256(data)
	actual := fmt.Sprintf("%x", hash)
	return actual == expected
}
