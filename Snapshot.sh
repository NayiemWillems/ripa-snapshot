#!/bin/bash

###############################################################################
#
#
#               8888888b.            8888888888 Y88b   d88P 
#               888   Y88b           888         Y88b d88P  
#               888    888           888          Y88o88P   
#               888   d88P           8888888       Y888P    
#               8888888P"            888           d888b    
#               888 T88b             888          d88888b   
#               888  T88b            888         d88P Y88b  
#               888   T88b           8888888888 d88P   Y88b 
#
# gsilvestri / v1.0 / 2018-03-26
# Inspired by Tharude (Ark.io) excellent ark_snapshot.sh script.
#
# Note: I'm using Nginx instead of NodeJS Ripa-Explorer to share the files.
#
# - Save to /home/##USER##/NewSnapshot.sh
#
# - chmod 700 /home/##USER##/NewSnapshot.sh
#
# - Edit FinalDirectory variable
#   Make sure it's writable by snapshot user and readable by nginx user.
#
# - Edit Crontab
#      crontab -u ##USER## -e
#      2,17,32,47 * * * * /home/##USER##/NewSnapshot.sh > /dev/null 2>&1 &
#
###############################################################################

RipaNetwork="mainnet"
RipaNodeDirectory="$HOME/ripa-node"
SnapshotDirectory='/opt/nginx/snapshot.ripaex.io'

### Test ripa-node Started
RipaNodePid=$( pgrep -a "node" | grep ripa-node | awk '{print $1}' )
if [ "$RipaNodePid" != "" ] ; then

    ### Delete Snapshot(s) older then 6 hours
    find $SnapshotDirectory -name "ripa_$RipaNetwork_*" -type f -mmin +360 -delete

    ### Write SeedNodeFile
#   RipaNodeConfig="$RipaNodeDirectory/config.$RipaNetwork.json"
    RipaNodeConfig="$RipaNodeDirectory/config.json"
    SeedNodeFile='/tmp/ripa_seednode'
    echo '' > $SeedNodeFile
    cat $RipaNodeConfig | jq -c -r '.peers.list[]' | while read Line; do
        SeedNodeAddress="$( echo $Line | jq -r '.ip' ):$( echo $Line | jq -r '.port' )"
        echo "$SeedNodeAddress" >>  "$SeedNodeFile"
    done

    ### Load SeedNodeFile in Memory & Remove SeedNodeFile
    declare -a SeedNodeList=()
    while read Line; do
        SeedNodeList+=($Line)
    done < $SeedNodeFile
    rm -f $SeedNodeFile

    ### Get highest Height from 8 random seed nodes
    SeedNodeCount=${#SeedNodeList[@]}
    for (( TopHeight=0, i=1; i<=8; i++ )); do
        RandomOffset=$(( RANDOM % $SeedNodeCount ))
        SeedNodeUri="http://${SeedNodeList[$RandomOffset]}/api/loader/status/sync"
        SeedNodeHeight=$( curl --max-time 2 -s $SeedNodeUri | jq -r '.height' )
        if [ "$SeedNodeHeight" -gt "$TopHeight" ]; then TopHeight=$SeedNodeHeight; fi
    done

    ### Get local ripa-node height
    LocalHeight=$( curl --max-time 2 -s 'http://127.0.0.1:5500/api/loader/status/sync' | jq '.height' )

    ### Test ripa-node Sync.
    if [ "$LocalHeight" -eq "$TopHeight" ]; then

        ForeverPid=$( forever --plain list | grep $RipaNodePid | sed -nr 's/.*\[(.*)\].*/\1/p' )
        cd $RipaNodeDirectory

        ### Stop ripa-node
        forever --plain stop $ForeverPid > /dev/null 2>&1 &
        sleep 1

        ### Dump Database
        SnapshotFilename='ripa_'$RipaNetwork'_'$LocalHeight
        pg_dump -O "ripa_$RipaNetwork" -Fc -Z6 > "$SnapshotDirectory/$SnapshotFilename"
        sleep 1

        ### Start ripa-node
#       forever --plain start app.js --genesis "genesisBlock.$RipaNetwork.json" --config "config.$RipaNetwork.json" > /dev/null 2>&1 &
        forever --plain start app.js --genesis "genesisBlock.json" --config "config.json" > /dev/null 2>&1 &

        ### Update Symbolic Link
        rm -f "$SnapshotDirectory/current"
        ln -s "$SnapshotDirectory/$SnapshotFilename" "$SnapshotDirectory/current"
    fi
fi