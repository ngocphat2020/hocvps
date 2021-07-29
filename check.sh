#!/bin/bash
clear
#YUM-APT
if  [ ! -e '/usr/bin/wget' ] || [ ! -e '/usr/bin/fio' ] || [ ! -e '/usr/bin/ioping' ] || [ ! -e '/usr/bin/sysbench' ] ||  [ ! -e '/usr/sbin/virt-what' ]
then
	echo -e "@Script test v1.0 by Quang Trung - https://engviet.net"
	echo -e "_________________________________________________"
	echo -e "Dang cai dat... Vui long doi - Please wait..."
	yum clean all > /dev/null 2>&1 && yum install -y epel-release > /dev/null 2>&1 && yum install -y fio sysbench ioping> /dev/null 2>&1 || (  apt-get update > /dev/null 2>&1 && apt-get install -y wget fio ioping sysbench virt-what > /dev/null 2>&1 )
fi

#TextFormat
endformat='\033[0m'
bold='\033[1m'
dim='\033[2m'
italic='\033[3m'
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'

# check root
[[ $EUID -ne 0 ]] && echo -e "${RED}Error:${endformat} Can chay script bang tai khoan root!" && exit 1

#CPU-core/Numjobs
cpu_name=`awk -F: '/model name/ {name=$2} END {print name}' /proc/cpuinfo | sed 's/^[ \t]*//;s/[ \t]*$//'`
freq=$( awk -F: '/cpu MHz/ {freq=$2} END {print freq}' /proc/cpuinfo | sed 's/^[ \t]*//;s/[ \t]*$//' )
cpu_cores=$( awk -F: '/model name/ {core++} END {print core}' /proc/cpuinfo)
numjobs=$((cpu_cores * 4))
if [ "$numjobs" -gt 32 ]; then
	numjobs=32
fi

#Virtua or not
virtua=$(virt-what)
if [[ ${virtua} ]]; then
	virt="$virtua"
	servps="VPS"
else
	virt="No"
	servps="Server"
fi

#RAM/SWAP-Info
tram=$( free -m | awk '/Mem/ {print $2}' )
uram=$( free -m | awk '/Mem/ {print $3}' )
swap=$( free -m | awk '/Swap/ {print $2}' )
uswap=$( free -m | awk '/Swap/ {print $3}' )

#DISK
calc_disk() {
	local total_size=0
	local array=$@
	for size in ${array[@]}
	do
		[ "${size}" == "0" ] && size_t=0 || size_t=`echo ${size:0:${#size}-1}`
		[ "`echo ${size:(-1)}`" == "M" ] && size=$( awk 'BEGIN{printf "%.1f", '$size_t' / 1024}' )
		[ "`echo ${size:(-1)}`" == "T" ] && size=$( awk 'BEGIN{printf "%.1f", '$size_t' * 1024}' )
		[ "`echo ${size:(-1)}`" == "G" ] && size=${size_t}
		total_size=$( awk 'BEGIN{printf "%.1f", '$total_size' + '$size'}' )
	done
	echo ${total_size}
}
disk_size1=($( LANG=C df -hPl | grep -wvE '\-|none|tmpfs|devtmpfs|by-uuid|chroot|Filesystem' | awk '{print $2}' ))
disk_size2=($( LANG=C df -hPl | grep -wvE '\-|none|tmpfs|devtmpfs|by-uuid|chroot|Filesystem' | awk '{print $3}' ))
disk_total_size=$( calc_disk ${disk_size1[@]} )
disk_used_size=$( calc_disk ${disk_size2[@]} )

#uptime
up=$( awk '{a=$1/86400;b=($1%86400)/3600;c=($1%3600)/60} {printf("%d days, %d hour %d min\n",a,b,c)}' /proc/uptime )

#DD
io_test() {
    (LANG=C dd if=/dev/zero of=test_$$ bs=64k count=16k conv=fdatasync && rm -f test_$$ && sync && echo 3 > /proc/sys/vm/drop_caches ) 2>&1 | awk -F, '{io=$NF} END { print io}' | sed 's/^[ \t]*//;s/[ \t]*$//'
}
dd_test() {
	io1=$( io_test )
	echo "I/O (Chay lan 1/1st run)        : $io1"
	io2=$( io_test )
	echo "I/O (Chay lan 2/2nd run)        : $io2"
	io3=$( io_test )
	echo "I/O (Chay lan 3/3rd run)        : $io3"
	ioraw1=$( echo $io1 | awk 'NR==1 {print $1}' )
	[ "`echo $io1 | awk 'NR==1 {print $2}'`" == "GB/s" ] && ioraw1=$( awk 'BEGIN{print '$ioraw1' * 1024}' )
	ioraw2=$( echo $io2 | awk 'NR==1 {print $1}' )
	[ "`echo $io2 | awk 'NR==1 {print $2}'`" == "GB/s" ] && ioraw2=$( awk 'BEGIN{print '$ioraw2' * 1024}' )
	ioraw3=$( echo $io3 | awk 'NR==1 {print $1}' )
	[ "`echo $io3 | awk 'NR==1 {print $2}'`" == "GB/s" ] && ioraw3=$( awk 'BEGIN{print '$ioraw3' * 1024}' )
	ioall=$( awk 'BEGIN{print '$ioraw1' + '$ioraw2' + '$ioraw3'}' )
	ioavg=$( awk 'BEGIN{printf "%.1f", '$ioall' / 3}' )
	echo "Trung Binh/Average              : $ioavg MB/s"
}
#FIO
fio_test_read_single() {
	if [ -e '/usr/bin/fio' ]; then
		echo -e "${dim}${italic}DOC NGAU NHIEN/RANDOM READ - Cang cao cang tot${endformat}"
		local tmp=$(mktemp)
    fio --randrepeat=0 --ioengine=libaio --direct=1 --group_reporting=1 --numjobs=$numjobs --gtod_reduce=1 --name=fio_test --filename=fio_test --bs=4k --iodepth=64 --size=1G --readwrite=randread --output="$tmp" > /dev/null 2>&1

		local iops_read=`grep "IOPS=" "$tmp" | grep read | awk -F[=,]+ '{print $2}'`

		echo "Single Read IOPS                : $iops_read"

		rm -f $tmp fio_test
	else
		echo "Khong the kiem tra muc nay, lien he admin de duoc ho tro!"
	fi
}

fio_test_write_single() {
	if [ -e '/usr/bin/fio' ]; then
		echo -e "${dim}${italic}GHI NGAU NHIEN/RANDOM WRITE - Cang cao cang tot${endformat}"
		local tmp=$(mktemp)
    fio --randrepeat=0 --ioengine=libaio --direct=1 --group_reporting=1 --numjobs=$numjobs --gtod_reduce=1 --name=fio_test --filename=fio_test --bs=4k --iodepth=64 --size=1G --readwrite=randwrite --output="$tmp" > /dev/null 2>&1

		local iops_write=`grep "IOPS=" "$tmp" | grep write | awk -F[=,]+ '{print $2}'`

		echo "Single Write IOPS               : $iops_write"

		rm -f $tmp fio_test
	else
		echo "Khong the kiem tra muc nay, lien he admin de duoc ho tro!"
	fi
}

fio_test_read_write_mix() {
	if [ -e '/usr/bin/fio' ]; then
		echo -e "${dim}${italic}DOC GHI NGAU NHIEN/READ,WRITE MIXED - Cang cao cang tot${endformat}"
		local tmp=$(mktemp)
    fio --randrepeat=0 --ioengine=libaio --direct=1 --group_reporting=1 --numjobs=$numjobs --gtod_reduce=1 --name=fio_test --filename=fio_test --bs=4k --iodepth=64 --size=1G --readwrite=randrw --rwmixread=75 --output="$tmp" > /dev/null 2>&1

		local iops_read=`grep "IOPS=" "$tmp" | grep read | awk -F[=,]+ '{print $2}'`
		local iops_write=`grep "IOPS=" "$tmp" | grep write | awk -F[=,]+ '{print $2}'`

		echo "Read IOPS                       : $iops_read"
		echo "Write IOPS                      : $iops_write"

		rm -f $tmp fio_test
	else
		echo "Khong the kiem tra muc nay, lien he admin de duoc ho tro!"
	fi
}

fio_test_sequential_read() {
	if [ -e '/usr/bin/fio' ]; then
		echo -e "${dim}${italic}DOC TUAN TU/SEQUENTIAL READ - Cang cao cang tot${endformat}"
		local tmp=$(mktemp)
    fio --randrepeat=0 --ioengine=libaio --direct=1 --group_reporting=1 --numjobs=$numjobs --gtod_reduce=1 --name=fio_test --filename=fio_test --bs=1M --iodepth=64 --size=1G --readwrite=read --output="$tmp" > /dev/null 2>&1

		local bw_read=`grep "bw=" "$tmp"|grep READ|awk -F"[()]" '{print $2}'`

		echo "Sequential Read performance     : $bw_read"

		rm -f $tmp fio_test
	else
		echo "Khong the kiem tra muc nay, lien he admin de duoc ho tro!"
	fi
}

fio_test_sequential_write() {
	if [ -e '/usr/bin/fio' ]; then
		echo -e "${dim}${italic}GHI TUAN TU/SEQUENTIAL WRITE - Cang cao cang tot${endformat}"
		local tmp=$(mktemp)
    fio --randrepeat=0 --ioengine=libaio --direct=1 --group_reporting=1 --numjobs=$numjobs --gtod_reduce=1 --name=fio_test --filename=fio_test --bs=1M --iodepth=64 --size=1G --readwrite=write --output="$tmp" > /dev/null 2>&1

		local bw_write=`grep "bw=" "$tmp"|grep WRITE|awk -F"[()]" '{print $2}'`

		echo "Sequential Write performance    : $bw_write"

		rm -f $tmp fio_test
	else
		echo "Khong the kiem tra muc nay, lien he admin de duoc ho tro!"
	fi
}

#IOPING
ioping_test() {
	latency=`ioping -c 10 .|tail -1|cut -d "/" -f5|awk '{print $1$2}'`
	echo "Do Tre/ Latency       : $latency"
}

#sysbench CPU
sysbench_test_cpu() {
	sysbench cpu --cpu-max-prime=20000 run|grep -E 'time:|avg:|max:'|cut -d ":" -f2 > tmp_CPU_sysbench
	total_time=`cat tmp_CPU_sysbench|awk '{print $1}'|sed '1!d'`
	avg_time=`cat tmp_CPU_sysbench|awk '{print $1}'|sed '2!d'`
	max_time=`cat tmp_CPU_sysbench|awk '{print $1}'|sed '3!d'`

	echo "Tong/ Total Time    : $total_time"
	echo "Trung Binh/ Average Time  : $avg_time ms"
	echo "Toi Da/ Maximum Time  : $max_time ms"

	rm -f tmp_CPU_sysbench > /dev/null 2>&1
}

#sysbench RAM
sysbench_test_ram() {
	sysbench memory --memory-block-size=1K --memory-scope=global --memory-total-size=100G --memory-oper=read run|grep 'sec'|cut -d "(" -f2|cut -d ")" -f1 > tmp_RAM_sysbench_READ
	sysbench memory --memory-block-size=1K --memory-scope=global --memory-total-size=100G --memory-oper=write run|grep 'sec'|cut -d "(" -f2|cut -d ")" -f1 > tmp_RAM_sysbench_WRITE
	read_operat_perform=`cat tmp_RAM_sysbench_READ|sed '1!d'`
	read_transfer=`cat tmp_RAM_sysbench_READ|sed '2!d'`
	write_operat_perform=`cat tmp_RAM_sysbench_WRITE|sed '1!d'`
	write_transfer=`cat tmp_RAM_sysbench_WRITE|sed '2!d'`

	echo "READ Operations Performed        : $read_operat_perform"
	echo "READ Transferred                 : $read_transfer"
	echo "WRITE Operations Performed       : $write_operat_perform"
	echo "WRITE Transferred                : $write_transfer"

	rm -f tmp_RAM_sysbench_READ > /dev/null 2>&1
	rm -f tmp_RAM_sysbench_WRITE > /dev/null 2>&1
}

speed_test() {
	local speedtest=$(wget -4O /dev/null -T300 $1 2>&1 | awk '/\/dev\/null/ {speed=$3 $4} END {gsub(/\(|\)/,"",speed); print speed}')
	local ipaddress=$(ping -c1 -n `awk -F'/' '{print $3}' <<< $1` | awk -F'[()]' '{print $2;exit}')
	local nodeName=$2
	printf "${YELLOW}%-40s${GREEN}%-16s${RED}%-14s${endformat}\n" "${nodeName}" "${ipaddress}" "${speedtest}"
}
speed_test_v6() {
	local speedtest=$(wget -6O /dev/null -T300 $1 2>&1 | awk '/\/dev\/null/ {speed=$3 $4} END {gsub(/\(|\)/,"",speed); print speed}')
	local ipaddress=$(ping6 -c1 -n `awk -F'/' '{print $3}' <<< $1` | awk -F'[()]' '{print $2;exit}')
	local nodeName=$2
	printf "${YELLOW}%-40s${GREEN}%-16s${RED}%-14s${endformat}\n" "${nodeName}" "${ipaddress}" "${speedtest}"
}
speed() {
	speed_test 'https://lax-ca-us-ping.vultr.com/vultr.com.100MB.bin' 'Vultr, Los Angeles, CA'
	speed_test 'https://wa-us-ping.vultr.com/vultr.com.100MB.bin' 'Vultr, Seattle, WA'
	speed_test 'http://speedtest.tokyo2.linode.com/100MB-tokyo.bin' 'Linode, Tokyo, JP'
	speed_test 'http://speedtest.singapore.linode.com/100MB-singapore.bin' 'Linode, Singapore, SG'
	speed_test 'http://speedtest.hkg02.softlayer.com/downloads/test100.zip' 'Softlayer, HongKong, CN'
	speed_test 'http://speedtest1.vtn.com.vn/speedtest/random4000x4000.jpg' 'VNPT, Ha Noi, VN'
	speed_test 'http://speedtest5.vtn.com.vn/speedtest/random4000x4000.jpg' 'VNPT, Da Nang, VN'
	speed_test 'http://speedtest3.vtn.com.vn/speedtest/random4000x4000.jpg' 'VNPT, Ho Chi Minh, VN'
	speed_test 'http://speedtestkv1a.viettel.vn/speedtest/random4000x4000.jpg' 'Viettel Network, Ha Noi, VN'
	speed_test 'http://speedtestkv3a.viettel.vn/speedtest/random4000x4000.jpg' 'Viettel Network, Ho Chi Minh, VN'
	speed_test 'http://speedtesthn.fpt.vn/speedtest/random4000x4000.jpg' 'FPT Telecom, Ha Noi, VN'
	speed_test 'http://speedtest.fpt.vn/speedtest/random4000x4000.jpg' 'FPT Telecom, Ho Chi Minh, VN'
}

echo "Thoi Gian Kiem Tra / Checked time `date`"
echo -e "\e[1;4m\e[30;48;5;82m $servps THONG SO/INFO \e[0m"
echo "Cong nghe ao hoa/ Virtualization    : $virt"
echo "Hang CPU/ CPU model                 : $cpu_name"
echo "Tan So CPU/ CPU frequency           : $freq MHz"
echo "So nhan CPU/ CPU cores              : $cpu_cores"
echo "Dung luong Ram/ Ram storage         : $tram MB ($uram MB Da su dung/ Used)"
echo "Dung luong Swap/ Swap storage       : $swap MB ($uswap MB Da su dung/ Used)"
echo "Dung luong o cung/ Disk size        : $disk_total_size GB ($disk_used_size GB Da su dung/ Used)"
echo "Thoi gian hoat dong/ Uptime         : $up"
echo -e "\e[1;4m\e[30;48;5;82m dd TEST - Cang Cao Cang tot / Higher is better \e[0m"
dd_test
echo -e "\e[1;4m\e[30;48;5;82m Hieu Nang O Cung / Flexible I/O Tester (FIO)\e[0m"
#fio_test_read_single
#fio_test_write_single
#fio_test_read_write_mix
fio_test_sequential_read
fio_test_sequential_write
echo -e "\e[1;4m\e[30;48;5;82m IOPING LATENCY - Cang thap cang tot / Lower is better \e[0m"
ioping_test
echo -e "\e[1;4m\e[30;48;5;82m CPU TEST - Cang thap cang tot / Lower is better \e[0m"
sysbench_test_cpu
echo -e "\e[1;4m\e[30;48;5;82m RAM TEST - Cang cao cang tot / Higher is better \e[0m"
sysbench_test_ram
echo -e "\e[1;4m\e[30;48;5;82m SPEEDTEST \e[0m"
printf "%-40s%-16s%-14s\n" "Ten Dia Diem/Node Name" "IPv4 address" "Toc Do Tai/Download Speed"
speed
