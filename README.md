# TG68K.C

switchable 68K CPU-Core

The TG68K.C is an IP core for FPGAs. It can be easily switched between a 68000, a 68010 and a 68020.
There are now many projects in the retro computer area that use this core. There was a lot of feedback from this area. So the core could develop very well. Many bugs could also be eliminated.
The core does not value cycle accuracy. The core saves the FPGA resources with a good execution speed. 



Der TG68K.C ist ein IP Core fuer FPGAs. Er kann auf einfache Weise zwischen einem 68000, einem 68010 und einem 68020 umgeschaltet werden. 
Es gibt inzwischen viele Projekte im Retrocomputer Bereich die diesen Core verwenden. Aus diesem Bereich gab es viele Rückmeldungen. So konnte der Core sehr gut weiter entwickelt werden. Ebenso konnten dadurch viele Bugs beseitigt werden. 
Der Core legt keinen Wert auf Zyklusgenauigkeit. Der Core schont die FPGA Resourcen bei einer guten Ausführungsgeschwindigkeit.


## Key Features of the TG68K:
- **Configurable CPU modes**: 68000, 68010, or 68020 instruction sets
- **Modular ALU** with optional hardware multiplier and barrel shifter
- **Bit field unit** for 68020 bit field instructions
- **Complete exception handling** including interrupts, traps, and bus errors
- **Flexible memory interface** supporting both synchronous and asynchronous modes
- **Microcode-based control** with extensive state machine for complex instructions

The design is highly configurable through generic parameters, allowing you to optimize for different use cases (area vs. performance) by enabling/disabling features like hardware multiplication, barrel shifting, and bit field operations.



## 1. **Architecture Diagram** (tg68k-architecture-diagram)
Shows the overall structure with:
- Top-level TG68K wrapper with external interface ports
- TG68KdotC_Kernel containing the main CPU logic
- TG68K_ALU with all arithmetic/logic units
- Key components: Microcode Sequencer, Register File, Special Registers, Memory Interface, Interrupt Controller, and Bus State Machine

<img width="1301" alt="tg68k-architecture-diagram" src="https://github.com/user-attachments/assets/1453c7c9-efd4-416a-be24-277585676ba5" />



## 2. **Data Flow Diagram** (tg68k-dataflow-diagram)
Illustrates how data moves through the processor:
- Instruction fetch and decode paths
- Register file connections to ALU
- Memory interface data paths
- Control signal routing
- Exception processing flow
- Detailed microcode sequences for various operations
  
<img width="1090" alt="tg68k-dataflow-diagram" src="https://github.com/user-attachments/assets/fdac01d1-4879-48f4-9979-d8a11418425f" />



## 3. **Module Hierarchy Diagram** (tg68k-hierarchy-diagram)
Details the hierarchical structure:
- Port definitions (input/output/bidirectional)
- Generic parameters for configuration
- Internal module connections
- ALU sub-components and their functions
- Interface signals between modules

<img width="1690" alt="tg68k-hierarchy-diagram" src="https://github.com/user-attachments/assets/f032d7ed-7150-45cb-af14-ff33607bf469" />



