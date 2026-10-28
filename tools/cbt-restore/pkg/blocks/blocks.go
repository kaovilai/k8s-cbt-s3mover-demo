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

var zeroChunk = make([]byte, DefaultBlockSize)

// BlockMetadata describes a block's location
type BlockMetadata struct {
	Offset   int64  `json:"offset"`
	Size     int64  `json:"size"`
	Checksum string `json:"checksum,omitempty"`
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
	readBack  *os.File
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
	if w.readBack != nil {
		_ = w.readBack.Close()
		w.readBack = nil
	}
	if w.device != nil {
		if err := w.device.Sync(); err != nil {
			return fmt.Errorf("failed to sync device: %w", err)
		}
		return w.device.Close()
	}
	return nil
}

// EnableReadBack opens a second handle for reading written blocks back.
func (w *Writer) EnableReadBack() error {
	if w.readBack != nil {
		return nil
	}
	f, err := os.Open(w.device.Name())
	if err != nil {
		return fmt.Errorf("failed to open device for read-back: %w", err)
	}
	w.readBack = f
	return nil
}

// ReadBlock reads size bytes at offset using the read-back handle.
func (w *Writer) ReadBlock(offset, size int64) ([]byte, error) {
	if w.readBack == nil {
		return nil, fmt.Errorf("read-back is not enabled")
	}
	if offset < 0 || size < 0 {
		return nil, fmt.Errorf("invalid read-back range: offset=%d size=%d", offset, size)
	}
	if _, err := w.readBack.Seek(offset, io.SeekStart); err != nil {
		return nil, fmt.Errorf("failed to seek to offset %d: %w", offset, err)
	}

	data := make([]byte, size)
	n, err := io.ReadFull(w.readBack, data)
	if err != nil && err != io.EOF && err != io.ErrUnexpectedEOF {
		return nil, fmt.Errorf("failed to read back block at offset %d: %w", offset, err)
	}
	if int64(n) != size {
		return nil, fmt.Errorf("short read-back at offset %d: got %d bytes, expected %d", offset, n, size)
	}
	return data, nil
}

// Size returns the size of the target device in bytes.
func (w *Writer) Size() (int64, error) {
	size, err := w.device.Seek(0, io.SeekEnd)
	if err != nil {
		return 0, fmt.Errorf("failed to get device size: %w", err)
	}
	if _, err := w.device.Seek(0, io.SeekStart); err != nil {
		return 0, fmt.Errorf("failed to seek back to start: %w", err)
	}
	return size, nil
}

// Zero writes length zero bytes starting at offset and syncs the device.
func (w *Writer) Zero(offset, length int64) error {
	if offset < 0 || length < 0 {
		return fmt.Errorf("invalid zero range: offset=%d length=%d", offset, length)
	}
	if _, err := w.device.Seek(offset, io.SeekStart); err != nil {
		return fmt.Errorf("failed to seek to offset %d: %w", offset, err)
	}

	for remaining := length; remaining > 0; {
		n := int64(len(zeroChunk))
		if remaining < n {
			n = remaining
		}
		written, err := w.device.Write(zeroChunk[:int(n)])
		if err != nil {
			return fmt.Errorf("failed to zero at offset %d: %w", offset+length-remaining, err)
		}
		if int64(written) != n {
			return fmt.Errorf("short zero write at offset %d: wrote %d bytes, expected %d", offset+length-remaining, written, n)
		}
		remaining -= n
	}

	return w.device.Sync()
}

// WriteBlock writes a block at the given offset
func (w *Writer) WriteBlock(block *BlockData) error {
	if block.Offset < 0 {
		return fmt.Errorf("invalid negative offset %d", block.Offset)
	}
	if block.Size != int64(len(block.Data)) {
		return fmt.Errorf("block size mismatch at offset %d: metadata says %d bytes, data has %d", block.Offset, block.Size, len(block.Data))
	}

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
