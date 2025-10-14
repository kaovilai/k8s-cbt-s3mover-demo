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

// BlockData represents a block of data
type BlockData struct {
	Offset   int64  `json:"offset"`
	Size     int64  `json:"size"`
	Checksum string `json:"checksum"`
	Data     []byte `json:"-"` // Don't marshal data in JSON
}

// Reader reads blocks from a device
type Reader struct {
	device    *os.File
	blockSize int64
}

// NewReader creates a new block reader
func NewReader(devicePath string, blockSize int64) (*Reader, error) {
	if blockSize <= 0 {
		blockSize = DefaultBlockSize
	}

	device, err := os.OpenFile(devicePath, os.O_RDONLY, 0)
	if err != nil {
		return nil, fmt.Errorf("failed to open device %s: %w", devicePath, err)
	}

	return &Reader{
		device:    device,
		blockSize: blockSize,
	}, nil
}

// Close closes the block reader
func (r *Reader) Close() error {
	if r.device != nil {
		return r.device.Close()
	}
	return nil
}

// ReadBlock reads a single block at the given offset
func (r *Reader) ReadBlock(offset int64, size int64) (*BlockData, error) {
	if size <= 0 {
		size = r.blockSize
	}

	// Seek to offset
	_, err := r.device.Seek(offset, io.SeekStart)
	if err != nil {
		return nil, fmt.Errorf("failed to seek to offset %d: %w", offset, err)
	}

	// Read data
	data := make([]byte, size)
	n, err := io.ReadFull(r.device, data)
	if err != nil && err != io.EOF && err != io.ErrUnexpectedEOF {
		return nil, fmt.Errorf("failed to read block at offset %d: %w", offset, err)
	}

	// Truncate if we read less than expected
	data = data[:n]

	// Calculate checksum
	hash := sha256.Sum256(data)
	checksum := fmt.Sprintf("%x", hash)

	return &BlockData{
		Offset:   offset,
		Size:     int64(n),
		Checksum: checksum,
		Data:     data,
	}, nil
}

// ReadBlocks reads multiple blocks
func (r *Reader) ReadBlocks(blocks []BlockMetadata) ([]*BlockData, error) {
	var results []*BlockData

	for _, block := range blocks {
		data, err := r.ReadBlock(block.Offset, block.Size)
		if err != nil {
			return nil, fmt.Errorf("failed to read block at offset %d: %w", block.Offset, err)
		}
		results = append(results, data)
	}

	return results, nil
}

// GetDeviceSize gets the total size of the device
func (r *Reader) GetDeviceSize() (int64, error) {
	// Seek to end to get size
	size, err := r.device.Seek(0, io.SeekEnd)
	if err != nil {
		return 0, fmt.Errorf("failed to get device size: %w", err)
	}

	// Seek back to start
	_, err = r.device.Seek(0, io.SeekStart)
	if err != nil {
		return 0, fmt.Errorf("failed to seek back to start: %w", err)
	}

	return size, nil
}

// BlockMetadata describes a block's location
type BlockMetadata struct {
	Offset int64 `json:"offset"`
	Size   int64 `json:"size"`
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
		// Sync to ensure data is written
		if err := w.device.Sync(); err != nil {
			return fmt.Errorf("failed to sync device: %w", err)
		}
		return w.device.Close()
	}
	return nil
}

// WriteBlock writes a block at the given offset
func (w *Writer) WriteBlock(block *BlockData) error {
	// Seek to offset
	_, err := w.device.Seek(block.Offset, io.SeekStart)
	if err != nil {
		return fmt.Errorf("failed to seek to offset %d: %w", block.Offset, err)
	}

	// Write data
	n, err := w.device.Write(block.Data)
	if err != nil {
		return fmt.Errorf("failed to write block at offset %d: %w", block.Offset, err)
	}

	if int64(n) != block.Size {
		return fmt.Errorf("partial write: wrote %d bytes, expected %d", n, block.Size)
	}

	return nil
}

// WriteBlocks writes multiple blocks
func (w *Writer) WriteBlocks(blocks []*BlockData) error {
	for _, block := range blocks {
		if err := w.WriteBlock(block); err != nil {
			return err
		}
	}

	// Sync after all writes
	return w.device.Sync()
}
