```
_/\/\/\/\/\_________________________/\/\______/\/\_______________________
_/\/\____/\/\___/\/\/\_____/\/\/\/\_/\/\/\__/\/\/\___/\/\/\___/\/\/\/\___
_/\/\/\/\/\___/\/\/\/\/\_/\/\__/\/\_/\/\/\/\/\/\/\_/\/\__/\/\_/\/\__/\/\_
_/\/\__/\/\___/\/\_________/\/\/\/\_/\/\__/\__/\/\_/\/\__/\/\_/\/\__/\/\_
_/\/\____/\/\___/\/\/\/\_______/\/\_/\/\______/\/\___/\/\/\___/\/\__/\/\_
_________________________/\/\/\/\________________________________________
```
**...provides a measurement tool set for wireless research with Atheros WiFi hardware**

### RegMon - in-Kernel MAC-Layer Monitoring
To perform the monitoring, we leverage the lightweight kernel-to-userspace debug file system (debugfs)
This serves two purposes:

1. it enables a a simple file-based configuration of RegMon for its in-kernel operations from the userspace
2. the actual trace-file from the kernel can be accessed via standard file read (e.g., with tail, cat) from the userspace.

For the actual measurements, it is possible to access Atheros control and status registers stored in the card memory through the PCI bus. Each of the Linux drivers (i.e., Madwifi, ath5k and ath9k) has its own C functions or macros to access the memory-mapped 32-bit register content, as shown at the bottom of the RegMon picture.

RegMon is implemented as a single kernel driver patch  for each of the supported three drivers, without the need for additional modules, daemons or user-space applications.
All main functions of RegMon and their interactions are:

![alt tag](https://cloud.githubusercontent.com/assets/1880886/9041313/d29e2c9e-3a07-11e5-95e3-ba5756927540.jpg)

The trace-file generated by RegMon is currently formatted as space separated list of measurement values, which turned out to be a sufficient format to parse and process the trace file for further analysis.

### How to install RegMon (under Linux OpenWrt)

1. copy RegMon patches (ath5k and/or ath9k) into openwrt/package/kernel/mac80211/patches 
2. re-build mac80211 subsystem by: make package/mac80211/{clean,compile} or re-build complite OpenWrt
3. install new mac80211 package or flash full image to your router

### How to use RegMon sampling
This first 7 registers are hardcoded into RegMon, which are:
- register_0 = TSF upper time stamp
- register_1 = TSF lower time stamp
- register_2 = MAC clock ticks
- register_3 = tx_busy state in clock ticks
- register_4 = rx_busy state in clock ticks
- register_5 = energy_detection state in clock ticks
- register_6 = TSF lower time stamp

- specify you own register reads via: 
```
echo XY-REGISTER-VALUE > /sys/kernel//debug/ieee80211/phy0/regmon/reg7..11
```
- set the sampling interval in nanoseconds (e.g. 50000ns = 20kHz sampling rate)
```
echo 50000 > /sys/kernel//debug/ieee80211/phy0/regmon/sampling_interval
```
- read RegMon data e.g. via:
```
tail -f /sys/kernel/debug/ieee80211/phy0/regmon/register_log
```

For availabe Atheros registers take a look at:
```
- ath5k:
  drivers/net/wireless/ath/ath5k/reg.h
- ath9k:
  drivers/net/wireless/ath/ath9k/ath9k/ar5008_initvals.h
  drivers/net/wireless/ath/ath9k/ath9k/ar9001_initvals.h
  drivers/net/wireless/ath/ath9k/ath9k/ar9002_initvals.h
```
- collect RegMon traces, parse, analyze and plot them
(in the script folder there are several unsorted awk, shell, R & python scipts that I wrote & use .. ToDo: clean-up)

### Example of RegMon's logging output
![alt tag](https://cloud.githubusercontent.com/assets/1880886/9058435/50d96800-3aa1-11e5-98c9-330c7aa15234.jpg)

### Parse logging output of RegMon to prepare ploting
In order to plot your register values that were collected by RegMon, someone could parse and precalculate certain values of interest.

The provided awk script **parse_default_RegMon-trace.awk** is such an example of preprocessing the output of RegMon for proper plotting. It performs the following operations with RegMon default output:
- calculate the absolute and relative difference of timestamps and register counters for each line sampled
- account for the baseband MAC clock rate at different IEEE 8021.11 modes, e.g:
 - 802.11g 20MHz channel width @2.4GHz -> MAC clock rate = 44MHz
 - 802.11a 20MHz channel width @5GHz   -> MAC clock rate = 40MHz
 - 802.11n 40MHz channel width @2.4GHz -> MAC clock rate = 88MHz
 - 802.11n 40MHz channel width @5GHz   -> MAC clock rate = 80MHz
 - all other MAC clocl rates at different channel width are a multiple of those given above
- change hexadecimal representation into decimal
- add an optional header to the parsed data

You can use the provided awk parser by issuing:
```
cat register_log | gawk --non-decimal-data -v header=1 -v clock=44 -f parse_default_RegMon-trace.awk
```

this leads to the following output:
```
ktime d_tx d_rx d_idle d_others
10001664 0 1183 878139 697
19998464 0 54376 822493 2480
30000128 145059 0 731288 3673
39998720 0 27276 851241 1152
49999872 0 28473 849755 1721
59998976 0 206086 670238 3462
70001664 0 122591 752627 5002
80001024 0 0 879591 0
90002176 0 159969 719757 387
```
where:
- ktime = kernel time stamp
- d_tx = absolute tx busy state count difference in ticks from previous sample
- d_rx = absolute rx busy state count difference in ticks from previous sample
- d_idle = absolute idle state count difference in ticks from previous sample
- d_others = absolute (energy_detection - rx_busy) state count difference in ticks from previous sample

... and now you can plot your mac busy state distribution over time. I prefer Rscript for plotting and so there is an example Rscript *plot_MAC-states_from_RegMon.r* which generates the output plot *RegMon.png*. For the Rscript to work you need R and the R packages: gglpot2, reshape2 and scales.
```
cat register_log | \
  gawk --non-decimal-data -v header=1 -v clock=44 -f parse_default_RegMon-trace.awk | \
  ./plot_MAC-states_from_RegMon.r
  
open RegMon.png
```

![alt tag](https://cloud.githubusercontent.com/assets/1880886/9155283/6ad13628-3eb3-11e5-96b3-f78cbcc6b7c5.png)

### Best practice for experimentation with RegMon
- RegMon traces at high sampling intervals create quite a bit of measurement data. The use of a compression stage is recommended and I prefer the lzop compressor which compresses a RegMon trace by a factor of ~4 with low cpu impact:
```
tail -f /sys/kernel/debug/ieee80211/phy0/regmon/register_log | lzop > /tmp/register_log.lzop
```

- if you do not have sufficient local disk space on your router, I use *netcat* on the router and client, to transfer the RegMon trace e.g. over ethernet:
 - on your router open a netcat server:
 ```
 ( while true; do netcat -l -p 1234 -e /bin/sh ; sleep 1; done ) &
 ```
 - on your Laptop connect to your router and save the actual trace file:
 ```
 START_REGMON="tail -n0 -F /sys/kernel/debug/ieee80211/phy0/regmon/register_log | lzop -1 -cf; exit"
 echo "${START_REGMON}" | netcat $your_router_IP 1234 > /tmp/register_log.lzo
 ```

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
### Where do I get the full description of RegMon ?
[Have a look at chapter 4 of my dissertaion](https://www.researchgate.net/publication/257412979_A_measurement_based_joint_power_and_rate_controller_for_IEEE_802.11_networks)
