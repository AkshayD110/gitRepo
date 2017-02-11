#!/bin/sh
# For any queries/feedback, please contact srinivas.vattikuti@oracle.com (or) narayan.kulkarni@oracle.com

# Usage : ./StartCounters.sh <StartAfterMinutes> <DurationOfCountersInMinutes> <NameOfTheTest - No blanks please>

if [ "$1" = "--help" ]
then
#	more countersHelp.txt
	more help.txt
	exit 1000
fi

# Initialize the configuration parameters
#. Counters.config
. ./Counters.config  #Atin: edited so that initialization happens correctly 

if (( $# != 3 ))
then
	echo "Usage : ./StartCounters.sh <StartAfterMinutes> <DurationOfCountersInMinutes> <NameOfTheTest>"
	echo "Use -> './StartCounters.sh --help' to get help"
	exit
fi
DATE=`date +%H_%M_%S_%d-%b`
CountersDir=Counters_${3}.$DATE
mkdir $CountersDir

(( startAfterSec = $1 * 60 ))

echo "Waiting for $1 minute(s) before taking the counters..."
sleep $startAfterSec

stopAfterMin=$2;

./StopCounters.sh $stopAfterMin $CountersDir &

echo "Taking the counters for $stopAfterMin minute(s)..."

# Start script for Average heap memory & disk usage calculation
./start_gc.sh $startAfterSec $stopAfterMin $CountersDir &
./disk_usage_reporter.sh $stopAfterMin $CountersDir &

# Generate AWR report if this is a DB machine
if [ "$dbMachineFlag" -eq "1" ]
then
	./generateAWR.sh $stopAfterMin $CountersDir/AWR_${CountersDir}.html &
else
	echo "dbMachineFlag is not set to 1. So, no AWR report will be generated"
fi

# Calling script to track external processes (if any)
#if [ "`echo $externalPIDs | tr ',' ' ' | wc -w`" -gt "0" ]
#then
#        ./getExtProcCPUAndMemInfo.sh $1 $2 $CountersDir > abc.log & 
#else
#        echo "There are no external processes to track."
#fi


cd $CountersDir

# Get machine configuration
numPhysicalProcessors=`cat /proc/cpuinfo | grep "physical id" | sort -u | wc -l`
coresPerCPU=`cat /proc/cpuinfo | grep "^cpu cores" | sort -u | awk '{print $NF}'`
numSiblings=`cat /proc/cpuinfo | grep "^siblings" | sort -u | awk '{print $NF}'`

totalMachineMemoryKB=`cat /proc/meminfo | grep MemTotal | tr -s ' ' | cut -f2 -d ' '`
totalMachineMemoryGB=`echo $totalMachineMemoryKB/1024/1024 |bc`

hyperthreaded="unknown"

if [ "$coresPerCPU" = "$numSiblings" ]
then
	hyperthreaded="Not Hyperthreaded"
else
	hyperthreaded="Hyperthreaded"
fi

echo "<html>" >> SummaryOfCounters.html
echo "<head>" >> SummaryOfCounters.html
echo "<title> $3 </title>" >> SummaryOfCounters.html
echo "</head>" >> SummaryOfCounters.html
echo "<body>" >> SummaryOfCounters.html

echo "<h1><u>Setup details</u></h1>" >> SummaryOfCounters.html
echo "<table border=\"1\">" >> SummaryOfCounters.html
echo "<tr><td>Test timestamp</td> <td>`date`</td></tr>" >> SummaryOfCounters.html
echo "<tr><td>PSR Test Scenario</td> <td>$3</td></tr>" >> SummaryOfCounters.html
echo "<tr><td>Test duration</td> <td>$stopAfterMin minute(s)</td></tr>" >> SummaryOfCounters.html
echo "<tr><td>Machine name</td> <td>`hostname`</td></tr>" >> SummaryOfCounters.html
echo "<tr><td>Machine CPU configuration</td> <td>${numPhysicalProcessors}P x ${coresPerCPU}C ($hyperthreaded) </td></tr>" >> SummaryOfCounters.html
echo "<tr><td>Machine memory</td> <td>${totalMachineMemoryGB}GB" >> SummaryOfCounters.html
echo "<tr><td> Ulimit core file size (-c)</td> <td>`ulimit -c`</td></tr>" >> SummaryOfCounters.html
echo "<tr><td> Ulimit open files (-n)</td> <td>`ulimit -n`</td></tr>" >> SummaryOfCounters.html
echo "<tr><td> Ulimit stack size (-s)</td> <td>`ulimit -s`</td></tr>" >> SummaryOfCounters.html
echo "</table>" >> SummaryOfCounters.html

# Get the process ids for which counters have to be taken.
javaHostpid=`ps -ef | grep "javahost" |grep "BI" |grep -v grep | awk '{print $2}'`
managedWLSBIserverpid=`ps -ef | grep "\-Dweblogic.Name" |grep -v grep | grep -v "\-Dweblogic.Name=AdminServer" | awk '{print $2}'`
adminWLSserverpid=`ps -ef | grep "\-Dweblogic.Name=AdminServer" |grep -v grep | awk '{print $2}'`
saspid=`ps -ef | grep nqsserver |grep -v grep | awk '{print $2}'`
sawpid=`ps -ef | grep sawserver |grep -v grep | awk '{print $2}'`
essbasepid=`ps -ef | grep "\-Doracle.component.type=EssbaseStudio" | grep -v grep | awk '{print $2}'`
essSvrPid=`ps -ef |grep ESSSVR | grep -v grep | awk '{print $2}'`

# Create processIDs file with process name and process ids for various processes.
# This is used by ExtractSummaryOfCounters.sh script.
echo OBIPS $sawpid > processIDs
echo OBIS $saspid >> processIDs
echo OBIJH $javaHostpid >> processIDs
echo WLSManagedServer $managedWLSBIserverpid >> processIDs
echo WLSAdminServer $adminWLSserverpid >> processIDs
echo EssbaseServer $essbasepid >> processIDs
echo EssSvr $essSvrPid >> processIDs

# If any process is not running, processIDs will not have entry
awk 'NF>=2' processIDs > tempprocessIDs
mv tempprocessIDs processIDs

echo "Processes being tracked are :"
cat processIDs
echo " "

# If multiple instances of same process are running, there will be more than
# one process id.
awk '{for (i=2;i<=NF;i++) printf "%s %ld\n", $1, $i}' processIDs > tempprocessIDs
mv tempprocessIDs processIDs

cat processIDs | grep -v WLSManagedServer | grep -v EssSvr > tempprocessIDs
managedServerPIDs=`cat processIDs | grep WLSManagedServer |awk '{print $NF}'`
for i in $managedServerPIDs
do
	server_name=`ps -ef | grep $i | grep -v grep | sed 's/ /\n/g' | grep "\-Dweblogic.Name" | awk -F= '{print $2}'`
	echo "$server_name $i" >> tempprocessIDs
done

essSvrPIDs=`cat processIDs | grep EssSvr | awk '{print $NF}'`
for i in $essSvrPIDs
do
	server_name=`ps -ef | grep $i | grep -v grep | awk '{print $9}'`
	echo "EssSvr($server_name) $i" >> tempprocessIDs
done
mv tempprocessIDs processIDs

# JVM parameters for Admin and Managed servers
echo "<h1><u>JVM details</u></h1>" >> SummaryOfCounters.html
echo "<table border=\"1\">" >> SummaryOfCounters.html
for i in $managedWLSBIserverpid
do
	server_name=`ps -ef | grep $i | grep -v grep | sed 's/ /\n/g' | grep "\-Dweblogic.Name" | awk -F= '{print $2}'`
	java_version=`ps -ef | grep $i |grep -v grep | sed 's/ /\n/g' | grep -i java | grep bin | awk -F/ '{print $(NF-2)}'`
	echo "<tr><td><b>WLSManagedServer(${i})</b></td> <td>$server_name</td></tr> <tr><td>JVM Used</td> <td>$java_version</td></tr>" >> SummaryOfCounters.html

	heap_params1=`ps -ef | grep $i |grep -v grep | sed 's/ /\n/g' | grep "\-Xm"`
	heap_params2=`ps -ef | grep $i |grep -v grep | sed 's/ /\n/g' | grep "\-XX:MaxPermSize"`
	echo "<tr><td>Heap parameters</td> <td>$heap_params1 $heap_params2</td></tr>" >> SummaryOfCounters.html

#	product=`ps -ef | grep $i | grep -v grep | sed 's/ /\n/g' | grep "/bin/java" | awk -F/ '{print $(NF-3)}'`
	product=`ps -ef | grep $i | grep -v grep | sed 's/ /\n/g' | grep "/bin/java" | awk -F/ '{for(i=1;i<NF-1;i++)print $i}'`
	product=`echo $product| tr ' ' '/'`
	echo "<tr><td>Java home</td> <td>/$product</td></tr>" >> SummaryOfCounters.html
done

for i in $adminWLSserverpid
do
	server_name=`ps -ef | grep $i | grep -v grep | sed 's/ /\n/g' | grep "\-Dweblogic.Name" | awk -F= '{print $2}'`
	java_version=`ps -ef | grep $i |grep -v grep | sed 's/ /\n/g' | grep -i java | grep bin | awk -F/ '{print $(NF-2)}'`
	echo "<tr><td><b>WLSAdminServer(${i})</b></td> <td>$server_name</td></tr> <tr><td>JVM Used</td> <td> $java_version </td></tr>" >> SummaryOfCounters.html

	heap_params1=`ps -ef | grep $i |grep -v grep | sed 's/ /\n/g' | grep "\-Xm"`
	heap_params2=`ps -ef | grep $i |grep -v grep | sed 's/ /\n/g' | grep "\-XX:MaxPermSize"`
	echo "<tr><td>Heap parameters</td> <td>$heap_params1 $heap_params2</td></tr>" >> SummaryOfCounters.html

#	product=`ps -ef | grep $i | grep -v grep | sed 's/ /\n/g' | grep "/bin/java" | awk -F/ '{print $(NF-3)}'`
	product=`ps -ef | grep $i | grep -v grep | sed 's/ /\n/g' | grep "/bin/java" | awk -F/ '{for(i=1;i<NF-1;i++)print $i}'`
	product=`echo $product| tr ' ' '/'`
        echo "<tr><td>Java home</td> <td>/$product</td></tr>" >> SummaryOfCounters.html
done

for i in $javaHostpid
do
	java_version=`ps -ef | grep $i |grep -v grep | sed 's/ /\n/g' | grep -i java | grep bin | awk -F/ '{print $(NF-2)}'`
        echo "<tr><td><b>JavaHostServer(${i})</b></td> <td>JavaHost</td></tr> <tr><td>JVM Used</td> <td> $java_version </td></tr>" >> SummaryOfCounters.html

        heap_params1=`ps -ef | grep $i |grep -v grep | sed 's/ /\n/g' | grep "\-Xm"`
        heap_params2=`ps -ef | grep $i |grep -v grep | sed 's/ /\n/g' | grep "\-XX:MaxPermSize"`
        echo "<tr><td>Heap parameters</td> <td>$heap_params1 $heap_params2</td></tr>" >> SummaryOfCounters.html

#       product=`ps -ef | grep $i | grep -v grep | sed 's/ /\n/g' | grep "/bin/java" | awk -F/ '{print $(NF-3)}'`
        product=`ps -ef | grep $i | grep -v grep | sed 's/ /\n/g' | grep "/bin/java" | awk -F/ '{for(i=1;i<NF-1;i++)print $i}'`
        product=`echo $product| tr ' ' '/'`
        echo "<tr><td>Java home</td> <td>/$product</td></tr>" >> SummaryOfCounters.html
done
echo "</table>" >> SummaryOfCounters.html

# Headers for counters' files.
for pid in $javaHostpid  $saspid $sawpid $managedWLSBIserverpid $adminWLSserverpid $essbasepid $essSvrPid
do
     top -b -n 1 -p $pid | awk 'NR==7' >> process_cpu.$pid
     ps -o "user,pid,etime,nice,cpu,time,pcpu,vsz,rss,args" -p $pid | awk 'NR==1' > mem_usage_${pid}.log
done

# Take the counters.
(( numSamples = stopAfterMin * 60 / interval )) 
vmstat 10 > VMSTAT_SWAP_Counters_etc.log &

# Machine CPU
sar -u $interval $numSamples >> sar_machine_cpu.log &

# Netowrk usage
sar -n DEV $interval $numSamples >> sar_network_usage.log &

# Core-wise CPU utilization
numSamplesForMpstat=`echo $numSamples-2 |bc`
mpstat -P ALL $interval $numSamplesForMpstat >> mpstat_core_wise_CPU_usage.log &

# System I/O statistics
iostat -x -k $interval $numSamples >> iostat_reads_writes.log &

# NFS I/O statistics
/usr/sbin/nfsiostat  $interval $numSamples >> nfsiostat_reads_writes.log &

# Counter for Disk utilization
count=1

# Calling script to track external processes (if any)
cd -
if [ "`echo $externalPIDs | tr ',' ' ' | wc -w`" -gt "0" ]
then
	./getExtProcCPUAndMemInfo.sh $1 $2 $CountersDir > /dev/null & 
else
	echo "There are no external processes to track."
fi
cd -

echo "User	System	Machine CPU" >top_machine_cpu.log
# Process CPU
myPIDfromTop=""

while (( 1 ))
do
  top -b -n 2 > top_sample.txt

  cat top_sample.txt | grep "Cpu(s)" | awk 'NR==2{print $2}' | awk -F% '{printf "%0.2f\t", $1}' >> top_machine_cpu.log
  cat top_sample.txt | grep "Cpu(s)" | awk 'NR==2{print $3}' | awk -F% '{printf "%0.2f\t", $1}' >> top_machine_cpu.log
  cat top_sample.txt | grep "Cpu(s)" | awk 'NR==2{print $5}' | awk -F% '{printf "%0.2f\n", 100-$1}' >> top_machine_cpu.log

   for pid in $javaHostpid  $saspid $sawpid $managedWLSBIserverpid $adminWLSserverpid $essbasepid $essSvrPid
   do
	#myPIDfromTop=`cat top_sample.txt | grep "$pid" | awk 'NR==2' |awk '{print $1}'`
	myPIDfromTop=`cat top_sample.txt | grep -w "$pid" | awk 'NR==2' |awk '{print $1}'` #Atin: added -w to prevent other similar pids showing up
	if [ "$myPIDfromTop" -eq "$pid" ]
	then
	     cat top_sample.txt | grep "$pid " | awk 'NR==2' >> process_cpu.$pid
	     ps -o "user,pid,etime,nice,cpu,time,pcpu,vsz,rss,args" -p $pid | grep " $pid "  >> mem_usage_${pid}.log
	fi
   done

	# Disk utilization report
	if [ "$count" -le "$numSamples" ]
	then
		for dir_name in `echo $DirectoriesToBeTracked | sed 's/,/\n/g'`
		do
#			du -sk $dir_name >> disk_utilization.log &
			du -sk $dir_name >> ResidualDirectorySizes.log
		done
		count=`echo $count+1 |bc`
	fi

   (( top_interval = interval - 3 ))
   sleep $top_interval
done
