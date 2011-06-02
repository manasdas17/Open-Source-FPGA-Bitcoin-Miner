##
#
# Copyright (c) 2011 fpgaminer@bitcoin-mining.com
#
#
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
# 
##


## TODO: Probe for Hardware and Device names and allow user to select.
## TODO: Allow user to enter username/password pairs and pool server info.
## TDOO: Save user configurations to a file and load on start.
## TODO: Log JSON-RPC information to a file instead of spitting it into the console, or make it a --verbose option.
## TODO: Long polling.
## TODO: Use the NONC virtual wire to measure hashrate.


package ifneeded TclCurl 7.19.6 [list load TclCurl7196.dll]\n[list source tclcurl.tcl]
package require TclCurl
package require json
source account.tcl

set instances [dict create]

proc find_instances {} {
	global instances
	foreach instance [get_insystem_source_probe_instance_info -hardware_name "USB-Blaster \[USB-0\]" -device_name $device_name] {
		dict set instances [lindex $instance 3] [lindex $instance 0]
	}
}

proc write_instance {name value} {
	global instances
	write_source_data -instance_index [dict get $instances $name] -value_in_hex -value $value
}

proc read_instance {name} {
	global instances
	return [read_probe_data -value_in_hex -instance_index [dict get $instances $name]]
}

proc readRPCRequest {size} {
	global rpc_request
	set chunk [string range $rpc_request 0 [expr {$size - 1}]]
	set rpc_request [string range $rpc_request $size 9999]
	
	return $chunk
}

proc writeHTTPResult {readData} {
	global httpresult
	set httpresult "${httpresult}${readData}"
	return
}

proc do_rpc_request {request} {
	global userpass
	global url
	global httpresult
	global rpc_request
	
	set httpresult ""
	set requestlen [string length $request]
	set curlerrors ""
	set rpc_request $request
	
	puts "Request: $request"
	
	curl::transfer -url $url -encoding identity -failonerror 0 -tcpnodelay 1 -userpwd $userpass -httpauth basic -httpheader [list "Content-type: application/json" "Content-Length: $requestlen" "Expect:"] -post 1 -readproc readRPCRequest -errorbuffer curlerrors -writeproc writeHTTPResult
	
	puts "Response: $httpresult"
	puts "Errors: $curlerrors"
	
	return [json::json2dict $httpresult]
}

proc reverseHex {hexstring} {
	set result ""
	
	for {set x 0} {$x < [string length $hexstring]} {incr x} {
		set piece [string range $hexstring $x [expr {$x+1}]]
		set result "${piece}${result}"
	
		[incr x]
	}
	
	return $result
}

proc get_work {} {
	set json_dict [do_rpc_request "{\"method\": \"getwork\", \"params\": \[\], \"id\":0}\r\n"]
	set json_result [dict get $json_dict result]

	set midstate [dict get $json_result midstate]
	set data [dict get $json_result data]
	set hash1 [dict get $json_result hash1]
	set target [dict get $json_result target]

	write_instance "STAT" [reverseHex $midstate]
	write_instance "DAT2" [string range [reverseHex $data] 64 127]
	
	return $data
}

proc wait_for_golden_ticket {timeout} {
	set begin_time [clock seconds]
	
	set current_r_nonce [read_instance NONC]
	puts "Current running nonce $current_r_nonce"
	set current_nonce [read_instance GNON]
	puts "Current nonce $current_nonce"

	puts "FPGA is now searching for lottery ticket..."

	while {1} {
		if { [string compare $current_nonce [read_instance GNON]] != 0} {
			break
		}
		
		if { [expr {[clock seconds] - $begin_time}] >= $timeout } {
			return ""
		}
		if { [expr {[clock seconds] - $begin_time}] >= 10 } {
			set begin_time [clock seconds]
			set current_r_nonce [read_instance NONC]
			puts "Current running nonce $current_r_nonce"
		}
	}

	puts "I've got a Golden Ticket!!"
	set nonce [read_instance GNON]
	puts $nonce
	
	return $nonce
}

proc submit_work {data nonce} {
	puts "Hex nonce: $nonce"
	set nonce [expr 0x$nonce]
	#set nonce [expr {$nonce - 132}] # No longer need to re-adjust nonce, the FPGA takes care of that.
	#puts "New nonce: $nonce"
	set nonce [format %08x $nonce]
	puts "New nonce hex: $nonce"

	set hexdata1 [string range $data 0 151]
	set hexdata2 [reverseHex $nonce]
	set hexdata3 [string range $data 160 255]
	set hexdata "${hexdata1}${hexdata2}${hexdata3}"

	puts "Original data: $data"
	puts "Golden data: $hexdata"

	puts "Submitting work ..."

	do_rpc_request "{\"method\": \"getwork\", \"params\": \[ \"$hexdata\" \], \"id\":1}\r\n"
}


find_instances

start_insystem_source_probe -hardware_name "USB-Blaster \[USB-0\]" -device_name $device_name

set nonce 0
while {0} {
	set last_nonce $nonce
	set nonce [read_instance NONC]
	set nonce [expr 0x$nonce]
	puts "Current running nonce [expr $nonce - $last_nonce]"
	after 1000
}

while {1} {
	# Get new work
	if [catch {set data [get_work]}] {
		puts "ERROR! (get_work) Waiting to try again ..."
		after 20000
		continue
	}
	
	if [catch {
		set golden_nonce [wait_for_golden_ticket 700]
	
		if { [string compare $golden_nonce ""] != 0 } {
		submit_work $data $golden_nonce
		}
	}] {
		puts "ERROR! (wait_for_golden_ticket) Waiting to try again ..."
		after 20000
		continue
	}
}



