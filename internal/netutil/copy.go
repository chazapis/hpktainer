package netutil

import (
	"encoding/binary"
	"fmt"
	"io"
	"net"

	"github.com/songgao/water"
)

// CopyFromTapToSocket reads packets from the TAP interface and writes them to the socket
// with a 4-byte length prefix.
func CopyFromTapToSocket(tap *water.Interface, conn net.Conn) error {
	buf := make([]byte, 65536) // Max Ethernet frame size is usually 1500, but can be higher. 64k is safe.
	lenBuf := make([]byte, 4)

	for {
		n, err := tap.Read(buf)
		if err != nil {
			return fmt.Errorf("read from tap error: %w", err)
		}

		// Write length prefix
		binary.BigEndian.PutUint32(lenBuf, uint32(n))
		if _, err := conn.Write(lenBuf); err != nil {
			return fmt.Errorf("write length to socket error: %w", err)
		}

		// Write payload
		if _, err := conn.Write(buf[:n]); err != nil {
			return fmt.Errorf("write payload to socket error: %w", err)
		}
	}
}

// CopyFromSocketToTap reads length-prefixed packets from the socket and writes them to the TAP interface.
func CopyFromSocketToTap(conn net.Conn, tap *water.Interface) error {
	lenBuf := make([]byte, 4)
	buf := make([]byte, 65536)

	for {
		// Read length prefix
		if _, err := io.ReadFull(conn, lenBuf); err != nil {
			return fmt.Errorf("read length from socket error: %w", err)
		}
		length := binary.BigEndian.Uint32(lenBuf)

		if length > uint32(len(buf)) {
			// This should theoretically not happen if both sides are well behaved,
			// but we should handle it to avoid panic or buffer overflow.
			// Ideally we might resize buffer, but for now error out.
			return fmt.Errorf("packet too large: %d", length)
		}

		// Read payload
		if _, err := io.ReadFull(conn, buf[:length]); err != nil {
			return fmt.Errorf("read payload from socket error: %w", err)
		}

		// Write to TAP
		if _, err := tap.Write(buf[:length]); err != nil {
			return fmt.Errorf("write to tap error: %w", err)
		}
	}
}
