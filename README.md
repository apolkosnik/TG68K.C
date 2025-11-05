# TG68K.C

switchable 68K CPU-Core

The TG68K.C is an IP core for FPGAs. It can be easily switched between a 68000, a 68010 and a 68020.
There are now many projects in the retro computer area that use this core. There was a lot of feedback from this area. So the core could develop very well. Many bugs could also be eliminated.
The core does not value cycle accuracy. The core saves the FPGA resources with a good execution speed.

## SuperScalar 4-Issue Redesign (Experimental)

This branch contains an **experimental redesign** of the TG68K as a **4-issue superscalar processor** with out-of-order execution capabilities.

### Key Features:
- **4-wide instruction fetch, decode, and dispatch** (up to 4 instructions per cycle)
- **Out-of-order execution** with 4 dedicated execution units (2 ALUs, 1 LSU, 1 Branch)
- **Register renaming** using 64 physical registers
- **Reorder Buffer (ROB)** with 32 entries for in-order commit
- **Reservation Stations** with 16 entries for instruction scheduling
- **Estimated performance**: 1.5-2.5 IPC (Instructions Per Cycle) vs 0.5-1.0 IPC for original

⚠️ **Warning**: This is a major architectural redesign and is **not production-ready**. Extensive testing and verification are required.

For detailed architecture documentation, see [SUPERSCALAR_DESIGN.md](SUPERSCALAR_DESIGN.md)

### New Files:
- `TG68K_SuperScalar_Pack.vhd` - Package with types and constants
- `TG68K_InstructionFetch.vhd` - 4-wide instruction fetch unit
- `TG68K_Decode.vhd` - Parallel 4-way decode logic
- `TG68K_RegisterRename.vhd` - Register renaming unit
- `TG68K_ReorderBuffer.vhd` - Reorder buffer for in-order commit
- `TG68K_ReservationStation.vhd` - Reservation stations and issue logic
- `TG68K_ExecutionUnit.vhd` - Generic execution unit
- `TG68K_PhysicalRegFile.vhd` - 64-entry physical register file
- `TG68K_SuperScalar_Core.vhd` - Top-level superscalar core integration

---

## Original TG68K.C

Der TG68K.C ist ein IP Core fuer FPGAs. Er kann auf einfache Weise zwischen einem 68000, einem 68010 und einem 68020 umgeschaltet werden.
Es gibt inzwischen viele Projekte im Retrocomputer Bereich die diesen Core verwenden. Aus diesem Bereich gab es viele Rückmeldungen. So konnte der Core sehr gut weiter entwickelt werden. Ebenso konnten dadurch viele Bugs beseitigt werden.
Der Core legt keinen Wert auf Zyklusgenauigkeit. Der Core schont die FPGA Resourcen bei einer guten Ausführungsgeschwindigkeit.
