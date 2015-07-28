```
_/\/\/\/\/\_________________________/\/\______/\/\_______________________
_/\/\____/\/\___/\/\/\_____/\/\/\/\_/\/\/\__/\/\/\___/\/\/\___/\/\/\/\___
_/\/\/\/\/\___/\/\/\/\/\_/\/\__/\/\_/\/\/\/\/\/\/\_/\/\__/\/\_/\/\__/\/\_
_/\/\__/\/\___/\/\_________/\/\/\/\_/\/\__/\__/\/\_/\/\__/\/\_/\/\__/\/\_
_/\/\____/\/\___/\/\/\/\_______/\/\_/\/\______/\/\___/\/\/\___/\/\__/\/\_
_________________________/\/\/\/\________________________________________
```
**...provides a measurement tool set for wireless research with Atheros WiFi hardware**

RegMon is implemented as a single kernel driver patch  for each of the supported three drivers, without the need for additional modules, daemons or user-space applications.
All main functions of RegMon and their interactions are:

![alt tag](https://cloud.githubusercontent.com/assets/1880886/8918836/070378ec-34bb-11e5-9452-9825a0f52bfa.jpg)

### RegMon - in-Kernel MAC-Layer Monitoring
To perform the monitoring, we leverage the lightweight kernel-to-userspace debug file system (debugfs)
This serves two purposes:

- (1) it enables a a simple file-based configuration of RegMon for its in-kernel operations from the userspace
- (2) the actual trace-file from the kernel can be accessed via standard file read (e.g., with tail, cat) from the userspace.

For the actual measurements, it is possible to access Atheros control and status registers stored in the card memory through the PCI bus. Each of the Linux drivers (i.e., Madwifi, ath5k and ath9k) has its own C functions or macros to access the memory-mapped 32-bit register content, as shown at the bottom of the RegMon picture.

The Linux kernel function 'readl()' is called to read the current register value at the memory address that was passed to it, respecting different host endianness and memory mapping specifics. For every register read, we store the current timestamp and the raw hexadecimal register values. Each column, except the first one holding the current timestamp, represents a register address specified through debugfs from the user-space. In our current implementation, we can monitor up to 12 registers in parallel. 
The main limiting factor for the number of registers is the memory footprint of the data structure to hold these values in the kernel.

### This RegMon git repo includes:

- RegMon measurement tool provided as patches for ath5k, ath9k and madwifi Linux drivers in OpenWRT
- shell scripts to set up measurements on OpenWRT WiFi routers
- parser scripts (mainly AWK) to bring the raw RegMon data in proper shape to ananlyse with R
- R scripts to perform statistics and generate plots

### How to reference to  RegMon ?
Just use the following bibtex :
```
@PhdThesis{Huehn2013,
 author      = {Thomas H{\"u}hn},
 title       = {A Measurement-Based Joint Power and Rate Controller for IEEE 802.11 Networks},
 school      = {Technische Universit{\"a}t Berlin, FG INET Prof. Anja Feldmann},
 year        = 2013,
 month       = July,
 urn         = {urn:nbn:de:kobv:83-opus4-39397},
 url         = {http://opus4.kobv.de/opus4-tuberlin/frontdoor/index/index/docId/3939}
}
```
