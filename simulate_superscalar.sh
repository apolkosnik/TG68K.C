#!/bin/bash
##############################################################################
# TG68K SuperScalar Simulation Script
# Requires: GHDL (VHDL simulator)
# Install: sudo apt-get install ghdl gtkwave
##############################################################################

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}TG68K SuperScalar Simulation${NC}"
echo -e "${GREEN}========================================${NC}"

# Check if GHDL is installed
if ! command -v ghdl &> /dev/null; then
    echo -e "${RED}ERROR: GHDL not found!${NC}"
    echo "Install with: sudo apt-get install ghdl"
    exit 1
fi

# Clean previous build
echo -e "${YELLOW}Cleaning previous build...${NC}"
rm -f *.o *.cf work-obj*.cf *.ghw

# Import and analyze VHDL files in dependency order
echo -e "${YELLOW}Analyzing VHDL files...${NC}"

# Base package (original TG68K)
if [ -f "TG68K_Pack.vhd" ]; then
    echo "  Analyzing TG68K_Pack.vhd..."
    ghdl -a --std=08 --ieee=synopsys -frelaxed-rules TG68K_Pack.vhd
else
    echo -e "${RED}ERROR: TG68K_Pack.vhd not found!${NC}"
    exit 1
fi

# SuperScalar package
echo "  Analyzing TG68K_SuperScalar_Pack.vhd..."
ghdl -a --std=08 --ieee=synopsys -frelaxed-rules TG68K_SuperScalar_Pack.vhd

# Component files (order doesn't matter much due to relaxed rules)
echo "  Analyzing component files..."
for file in \
    TG68K_InstructionFetch.vhd \
    TG68K_Decode.vhd \
    TG68K_Complete_Decoder.vhd \
    TG68K_RegisterRename.vhd \
    TG68K_ReorderBuffer.vhd \
    TG68K_ReservationStation.vhd \
    TG68K_ExecutionUnit.vhd \
    TG68K_PhysicalRegFile.vhd \
    TG68K_BranchPredictor.vhd \
    TG68K_LoadStoreQueue.vhd \
    TG68K_SimpleCache.vhd \
    TG68K_PerfCounters.vhd; do
    if [ -f "$file" ]; then
        echo "    - $file"
        ghdl -a --std=08 --ieee=synopsys -frelaxed-rules "$file"
    else
        echo -e "${YELLOW}    - $file (not found, skipping)${NC}"
    fi
done

# Top-level core
echo "  Analyzing TG68K_SuperScalar_Core.vhd..."
ghdl -a --std=08 --ieee=synopsys -frelaxed-rules TG68K_SuperScalar_Core.vhd

# Testbench
echo "  Analyzing TG68K_SuperScalar_tb.vhd..."
ghdl -a --std=08 --ieee=synopsys -frelaxed-rules TG68K_SuperScalar_tb.vhd

# Elaborate testbench
echo -e "${YELLOW}Elaborating testbench...${NC}"
ghdl -e --std=08 --ieee=synopsys -frelaxed-rules TG68K_SuperScalar_tb

# Run simulation
echo -e "${GREEN}Running simulation...${NC}"
echo -e "${GREEN}========================================${NC}"
ghdl -r --std=08 --ieee=synopsys -frelaxed-rules TG68K_SuperScalar_tb \
    --wave=superscalar_wave.ghw \
    --stop-time=2us \
    --assert-level=warning

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Simulation completed!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "Waveform saved to: superscalar_wave.ghw"
echo "View with: gtkwave superscalar_wave.ghw"
echo ""
echo -e "${YELLOW}Known limitations:${NC}"
echo "  - Memory interface repeats 16-bit data (all instructions see same word)"
echo "  - Branch prediction disabled (assumes all predictions correct)"
echo "  - Operand ready tracking simplified (assumes all ready)"
echo ""
