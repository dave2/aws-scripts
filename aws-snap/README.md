aws-snap
========

These two scripts maintain an instance-initated backup rotation, similar
to a traditional tape backup cycle.

A rotation has a label, and has a number of historical copies. The number
is passed on runtime, and therefore can be different for each rotation.

A snap can also be "promoted" from one rotation to another. An example
of this is to cherry pick the daily made on the 1st of the month to become
a monthly. Like the initial snap creation, after promption the number
of copies kepted in the target rotation can be culled to a specific number.

The handling of rotations is done by tagging snaps with two critical tags:

- Autosnap (which must be true), to indicate this is a snap that we manage
- BackupRotation containing the name of the rotation to affect

It will only ever touch snaps for volumes currently attached. If you 
detach a volume, it will *not* remove any snaps of the removed volume.

Example of usage using cron:

```
# make a backup daily, keep 10
0 2 * * * root /path/to/aws-snap.sh daily 10
# cherry pick last daily into a weekly on sundays, keep 6
10 2 * * 0 root /path/to/aws-snap-promote.sh daily weekly 6
# cherry pick last weekly into a monthly on 1st, keep forever
20 2 1 * * root /path/to/aws-snap-promote.sh weekly monthly -1
```

The scripts need specific permissions in EC2 to function. These can be
provided any means that AWS CLI tools accept. This can be either using
access keys for an account, or instance-role permissions.

A policy for access typically looks like:

```
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "Stmtxxxxxxxxxxx",
            "Effect": "Allow",
            "Action": [
                "ec2:CreateSnapshot",
                "ec2:DeleteSnapshot",
                "ec2:DescribeInstances",
                "ec2:DescribeVolumes",
                "ec2:DescribeSnapshots",
                "ec2:DescribeTags",
                "ec2:CreateTags"
            ],
            "Resource": [
                "*"
            ]
        }
    ]
}
```


