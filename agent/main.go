// orbit-agent — reads /proc on Linux, streams compact JSON
// snapshots to stdout every `interval` seconds. Exits when stdin closes
// (so SSH disconnect cleans up automatically).
package main

import (
	"bufio"
	"encoding/json"
	"flag"
	"io"
	"os"
	"strconv"
	"strings"
	"time"
)

type Snapshot struct {
	CPU      float64 `json:"cpu"`       // 0..1 across all cores
	MemUsed  uint64  `json:"mem_used"`  // bytes
	MemTotal uint64  `json:"mem_total"` // bytes
	NetRx    float64 `json:"net_rx_bps"`
	NetTx    float64 `json:"net_tx_bps"`
	Uptime   float64 `json:"uptime"` // seconds
	Host     string  `json:"host"`
	Ts       int64   `json:"ts"`
}

func main() {
	interval := flag.Float64("interval", 2.0, "sample interval in seconds")
	flag.Parse()

	host, _ := os.Hostname()
	enc := json.NewEncoder(os.Stdout)

	// Exit when stdin closes (parent SSH disconnected)
	go func() {
		io.Copy(io.Discard, os.Stdin)
		os.Exit(0)
	}()

	var prevCPU cpuTicks
	var prevNetRx, prevNetTx uint64
	var prevT = time.Now()
	primed := false

	ticker := time.NewTicker(time.Duration(*interval * float64(time.Second)))
	defer ticker.Stop()

	for {
		now := time.Now()
		elapsed := now.Sub(prevT).Seconds()
		prevT = now

		curCPU, _ := readCPUTicks()
		memUsed, memTotal, _ := readMem()
		rx, tx, _ := readNet()
		up, _ := readUptime()

		var cpuFrac float64
		var rxBps, txBps float64
		if primed && elapsed > 0 {
			cpuFrac = curCPU.fractionSince(prevCPU)
			rxBps = float64(rx-prevNetRx) / elapsed
			txBps = float64(tx-prevNetTx) / elapsed
		}
		prevCPU = curCPU
		prevNetRx = rx
		prevNetTx = tx
		primed = true

		snap := Snapshot{
			CPU: cpuFrac, MemUsed: memUsed, MemTotal: memTotal,
			NetRx: rxBps, NetTx: txBps, Uptime: up, Host: host,
			Ts: now.Unix(),
		}
		_ = enc.Encode(&snap) // newline-terminated, one line per snapshot
		_ = os.Stdout.Sync()

		<-ticker.C
	}
}

// --- /proc parsing ---

type cpuTicks struct{ user, nice, system, idle, iowait, irq, softirq, steal uint64 }

func (c cpuTicks) active() uint64 { return c.user + c.nice + c.system + c.irq + c.softirq + c.steal }
func (c cpuTicks) total() uint64  { return c.active() + c.idle + c.iowait }

func (c cpuTicks) fractionSince(prev cpuTicks) float64 {
	da := c.active() - prev.active()
	dt := c.total() - prev.total()
	if dt == 0 {
		return 0
	}
	return float64(da) / float64(dt)
}

func readCPUTicks() (cpuTicks, error) {
	f, err := os.Open("/proc/stat")
	if err != nil {
		return cpuTicks{}, err
	}
	defer f.Close()
	scanner := bufio.NewScanner(f)
	if !scanner.Scan() {
		return cpuTicks{}, scanner.Err()
	}
	fields := strings.Fields(scanner.Text()) // "cpu  u n s i io irq sirq steal ..."
	parse := func(i int) uint64 { v, _ := strconv.ParseUint(fields[i], 10, 64); return v }
	return cpuTicks{
		user: parse(1), nice: parse(2), system: parse(3), idle: parse(4),
		iowait: parse(5), irq: parse(6), softirq: parse(7), steal: parse(8),
	}, nil
}

func readMem() (used, total uint64, err error) {
	f, err := os.Open("/proc/meminfo")
	if err != nil {
		return 0, 0, err
	}
	defer f.Close()
	var memTotalKB, memAvailKB uint64
	scanner := bufio.NewScanner(f)
	for scanner.Scan() {
		line := scanner.Text()
		switch {
		case strings.HasPrefix(line, "MemTotal:"):
			memTotalKB = parseKB(line)
		case strings.HasPrefix(line, "MemAvailable:"):
			memAvailKB = parseKB(line)
		}
		if memTotalKB != 0 && memAvailKB != 0 {
			break
		}
	}
	total = memTotalKB * 1024
	if memAvailKB > memTotalKB {
		return 0, total, nil
	}
	used = (memTotalKB - memAvailKB) * 1024
	return used, total, nil
}

func parseKB(line string) uint64 {
	fields := strings.Fields(line) // "MemTotal: 24608580 kB"
	if len(fields) < 2 {
		return 0
	}
	v, _ := strconv.ParseUint(fields[1], 10, 64)
	return v
}

func readNet() (rx, tx uint64, err error) {
	f, err := os.Open("/proc/net/dev")
	if err != nil {
		return 0, 0, err
	}
	defer f.Close()
	scanner := bufio.NewScanner(f)
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		colon := strings.Index(line, ":")
		if colon < 0 {
			continue
		}
		iface := strings.TrimSpace(line[:colon])
		if iface == "lo" {
			continue
		}
		fields := strings.Fields(line[colon+1:])
		if len(fields) < 10 {
			continue
		}
		r, _ := strconv.ParseUint(fields[0], 10, 64)
		t, _ := strconv.ParseUint(fields[8], 10, 64)
		rx += r
		tx += t
	}
	return rx, tx, nil
}

func readUptime() (float64, error) {
	data, err := os.ReadFile("/proc/uptime")
	if err != nil {
		return 0, err
	}
	fields := strings.Fields(string(data))
	if len(fields) < 1 {
		return 0, nil
	}
	return strconv.ParseFloat(fields[0], 64)
}
