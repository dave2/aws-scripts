#!/bin/sh  

# aws-snap.sh [ <rotation_name> [ <copies_to_keep> ] ]
#
# Make a new snap of all attached volumes to the instance this is running
# on, and remove old snaps. "old" is defined an snaps greater than the
# passed count of snaps.
#
# Copyright (C) 2016 David Zanetti
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along
# with this program; if not, write to the Free Software Foundation, Inc.,
# 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
#

ROTATION=$1
KEEP=$2

if [ -z ${ROTATION} ]; then
 ROTATION=daily
fi

if [ -z "${KEEP}" ]; then
 KEEP=14
fi

# pull out the current state into shell variables
curl -s http://169.254.169.254/latest/dynamic/instance-identity/document > /tmp/aws-instance-$$.json
INSTANCE_ID=$(jq -r .instanceId /tmp/aws-instance-$$.json)
REGION_ID=$(jq -r .region /tmp/aws-instance-$$.json)
ACCOUNT_ID=$(jq -r .accountId /tmp/aws-instance-$$.json)

echo we are ${INSTANCE_ID} in ${REGION_ID}

# work out what volumes we have, and snap them all
VOLUMES=$(aws ec2 --region ${REGION_ID} describe-instances --instance-id ${INSTANCE_ID} | jq -r ".Reservations[].Instances[].BlockDeviceMappings[].Ebs?.VolumeId?")

echo volumes found: ${VOLUMES}

# snapshots can only be called on one volume at a time :(
for i in ${VOLUMES}; do

 # make the snap
 SNAP_ID=$(aws ec2 --region ${REGION_ID} create-snapshot --volume-id ${i} --description "Automatic snapshot for `hostname -f`" | jq -r .SnapshotId) 
 echo "started snap ${SNAP_ID} of ${i}"
 SNAP_IDS="${SNAP_IDS} ${SNAP_ID}"
done

# tag them
echo "tagging snaps"
aws ec2 --region ${REGION_ID} create-tags --resources ${SNAP_IDS} --tags Key=Autosnap,Value=true Key=OrigHost,Value=`hostname -f` Key=OrigInstance,Value=${INSTANCE_ID} Key=BackupCycle,Value=${ROTATION}

echo -n "waiting for snaps to complete..."
# wait until complete
aws ec2 --region ${REGION_ID} wait snapshot-completed --snapshot-id ${SNAP_IDS}
echo " done."

if [ "${KEEP}" -ne "-1" ]; then
 for i in ${VOLUMES}; do
  # find what snaps to delete that are too old
  DEL_SNAPS=$(aws ec2 --region ${REGION_ID} describe-snapshots --owner-id ${ACCOUNT_ID} --filters Name=tag-key,Values=Autosnap Name=tag-value,Values=true Name=tag-key,Values=BackupCycle Name=tag-value,Values=${ROTATION} Name=volume-id,Values=${i} | jq -r ".Snapshots|=sort_by(.StartTime) | .Snapshots|=reverse | .Snapshots[${KEEP}:] | .[].SnapshotId")
    
  # we can't do this in one call :(
  for j in ${DEL_SNAPS}; do
   echo "delete old snap ${j} of ${i}"
   aws ec2 --region ${REGION_ID} delete-snapshot --snapshot-id ${j}
  done
 done
fi # keep is not -1



