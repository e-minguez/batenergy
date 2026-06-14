#!/usr/bin/env bash

FILE=/tmp/batenergy.dat
ADP=(/sys/class/power_supply/A*)
BAT=(/sys/class/power_supply/BAT*)

USER="edu"
USERID=$(id -u ${USER})

[[ -e ${BAT[0]} ]] || exit

state=$1
sleep_type=$2

if [[ $state == "post" ]]; then
	sleep 2
fi

now=`date +'%s'`

# Detect if battery is charging or on mains.
# Returns via global CHARGING:
#   1 = plugged in and charging
#   0 = on battery (not charging)
is_charging() {
	local bat_path="${BAT[0]}"
	local status
	if [[ -f $bat_path/status ]]; then
		status=$(< "$bat_path/status")
		if [[ "$status" == "Charging" ]]; then
			CHARGING=1
			return
		fi
	fi
	# Fallback: check AC adapter online
	if [[ -f ${ADP[0]}/online ]]; then
		read online < "${ADP[0]}/online"
		(( online )) && CHARGING=1 || CHARGING=0
	else
		CHARGING=0
	fi
}

# Read an energy in mWh from /sys/class/power_supply.
# Some firmware only reports charge (in µAh), in which case we convert using a stable voltage.
read_energy() {
	local when=$1
	local -n var=energy_$when
	local bat_path="${BAT[0]}"
	if [[ -e $bat_path/energy_$when ]]; then
		(( var = $(< "$bat_path"/energy_$when) / 1000 )) # mWh
	else
		if [[ -z $voltage_ref ]]; then
			if [[ -e $bat_path/voltage_min_design ]]; then
				voltage_ref=$(< "$bat_path"/voltage_min_design)
			else
				voltage_ref=$(< "$bat_path"/voltage_now)
			fi
		fi
		(( var = $(< "$bat_path"/charge_$when) * voltage_ref / 1000000000 )) # mWh
	fi
}

read_energy now
read_energy full

# Report power source
if [[ -f ${ADP[0]}/online ]]; then
	read online < "${ADP[0]}/online"
	if (( online )); then
		echo "Currently on mains."
	else
		echo "Currently on battery."
	fi
fi

case $state in
"pre")
	is_charging
	if (( CHARGING )); then
		echo "Skipping save — battery is charging."
		exit 0
	fi
	echo "Saving time (${now}) and battery energy (${energy_now}) before sleeping ($sleep_type)."
	echo $now > $FILE
	echo $energy_now >> $FILE
	;;
"post")
	is_charging
	if (( CHARGING )); then
		echo "Skipping stats — battery is charging."
		exit 0
	fi
	exec 3<>$FILE
	read prev <&3
	read energy_prev <&3
	rm $FILE
	time_diff=$(($now - $prev)) # seconds
	if (( time_diff <= 0 )); then time_diff=1; fi
	days=$(($time_diff / (3600*24)))
	hours=$(($time_diff % (3600*24) / 3600))
	minutes=$(($time_diff % 3600 / 60))
	(( energy_diff = energy_now - energy_prev )) # mWh
	(( avg_rate = energy_diff * 3600 / time_diff )) # mW
	energy_diff_pct=$(bc <<< "scale=1;$energy_diff * 100 / $energy_full") # %
	avg_rate_pct=$(bc <<< "scale=2;$avg_rate * 100 / $energy_full") # %/h
	MESSAGE="Duration of $days days $hours hours $minutes minutes sleeping ($sleep_type).
Energy difference = ${energy_now} - ${energy_prev}
Battery energy change of $energy_diff_pct % ($energy_diff mWh) at an average rate of $avg_rate_pct %/h ($avg_rate mW)."
	echo "$MESSAGE"
	# Write message to a file for the user-level systemd service to pick up and display
	printf '%s' "$MESSAGE" > /run/user/${USERID}/batenergy.notify
	;;
esac
