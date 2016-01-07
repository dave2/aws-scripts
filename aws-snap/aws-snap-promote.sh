#!/bin/sh 

# aws-snap-promote.sh <source_rotation> <target_rotation> [ <keep_copies> ]
#
# Prompte an existing snapshot made by aws-snap.sh to a different rotation
# group. This allows you to cheery-pick snapshots for long term archives
# and implement multiple levels of rotation
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

ORIG=$1
ROTATION=$2
KEEP=$3

if [ -z ${ORIG} -or -z ${ROTATION} ]; then
 echo must pass origin group or target group
 exit 1
fi

if [ -z ${KEEP} ]; then
 KEEP=14
fi

# pull out the current state into shell variables
curl -s http://169.254.169.254/latest/dynamic/instance-identity/document > /tmp/aws-instance-$$.json
INSTANCE_ID=$(jq -r .instanceId /tmp/aws-instance-$$.json)
REGION_ID=$(jq -r .region /tmp/aws-instance-$$.json)
ACCOUNT_ID=$(jq -r .accountId /tmp/aws-instance-$$.json)

echo we are ${INSTANCE_ID} in ${REGION_ID}

# identify our volumes
VOLUMES=$(aws ec2 --region ${REGION_ID} describe-instances --instance-id ${INSTANCE_ID} | jq -r ".Reservations[].Instances[].BlockDeviceMappings[].Ebs?.VolumeId?")

echo volumes found: ${VOLUMES}

# we need to identify each snapshot to promote
for i in ${VOLUMES}; do

 # pull out the last volume for the original type
 PROMOTE_SNAP=$(aws ec2 --region ${REGION_ID} describe-snapshots --owner-id ${ACCOUNT_ID} --filters Name=tag-key,Values=Autosnap Name=tag-value,Values=true Name=tag-key,Values=BackupCycle Name=tag-value,Values=${ORIG} Name=volume-id,Values=${i} | jq -r ".Snapshots|=sort_by(.StartTime) | .Snapshots|=reverse | .Snapshots[0].SnapshotId  ")

 echo promoting ${PROMOTE_SNAP} from ${ORIG} to ${ROTATION}

 # this is done by re-tagging the snapshot
 aws ec2 --region ${REGION_ID} create-tags --resources ${PROMOTE_SNAP} --tags Key=Autosnap,Value=true Key=OrigHost,Value=`hostname -f` Key=OrigInstance,Value=${INSTANCE_ID} Key=BackupCycle,Value=${ROTATION}

done

# now purge older promoted snaps
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


