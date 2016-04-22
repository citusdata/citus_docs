.. _multi_node_aws:

Multi-node setup on AWS (Recommended)
================================================================================

This section describes the steps needed to set up a CitusDB cluster on AWS using the CloudFormation console.

To simplify the process of setting up a CitusDB cluster on `EC2 <http://aws.amazon.com/ec2/>`_, AWS users can use AWS CloudFormation. The CloudFormation template for CitusDB enables users to start a CitusDB cluster on AWS in just a few clicks, with pg_shard, for real-time transactional workloads, cstore_fdw, for columnar storage, and contrib extensions pre-installed. The template automates the installation and configuration process so that the users don’t need to do any extra configuration steps while installing CitusDB.

Please ensure that you have an active AWS account and an `Amazon EC2 key pair <http://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-key-pairs.html>`_ before proceeding with the next steps.

**Introduction**

`CloudFormation <http://aws.amazon.com/cloudformation/>`_ lets you create a "stack" of AWS resources, such as EC2 instances and security groups, from a template defined in a JSON file. You can create multiple stacks from the same template without conflict, as long as they have unique stack names.

Below, we explain in detail the steps required to setup a multi-node CitusDB cluster on AWS.

**1. Start a CitusDB cluster**

To begin, you can start a CitusDB cluster using CloudFormation by clicking the "Launch CitusDB on AWS" button on our downloads page.
This will take you directly to the AWS CloudFormation console.

Note: You might need to login to AWS at this step if you aren’t already logged in.

**2. Pick unique stack name**

In the console, pick a unique name for your stack and click Next.

.. image:: ../images/pick_name.png

Note: Please ensure that you choose unique names for all your clusters. Otherwise, the cluster creation may fail with the error “Template_name template already created”.


**3. Fill the form with details about your cluster**

In the form, you can customize your cluster setup by setting the availability zone, number of workers and the instance types. You also need to fill in the AWS keypair which you will use to access the cluster.

.. image:: ../images/aws_parameters.png

Note: If you want to launch a cluster in a region other than US East, you can update the region in the top-right corner of the AWS console as shown below.

.. image:: ../images/aws_region.png


**4. Acknowledge IAM capabilities**

The next screen displays Tags and a few advanced options. For simplicity, we use the default options and click Next.

Finally, you need to acknowledge IAM capabilities, which give the master node limited access to the EC2 APIs to obtain the list of worker IPs. Your AWS account needs to have IAM access to perform this step. After ticking the checkbox, you can click on Create.

.. image:: ../images/aws_iam.png


**5. Cluster launching**

After the above steps, you will be redirected to the CloudFormation console. You can click the refresh button on the top-right to view your stack. In about 10 minutes, stack creation will complete and the hostname of the master node will appear in the Outputs tab. 

.. image:: ../images/aws_cluster_launch.png

Note: Sometimes, you might not see the outputs tab on your screen by default. In that case, you should click on “restore” from the menu on the bottom right of your screen.
 
.. image:: ../images/aws_restore_icon.png

**Troubleshooting:**

You can use the cloudformation console shown above to monitor your cluster.

If something goes wrong during set-up, the stack will be rolled back but not deleted. In that case, you can either use a different stack name or delete the old stack before creating a new one with the same name.

**6. Login to the cluster**

Once the cluster creation completes, you can immediately connect to the master node using SSH with username ec2-user and the keypair you filled in. For example:-

::

	ssh -i citus-user-keypair.pem ec2-user@ec2-54-82-70-31.compute-1.amazonaws.com


**7. Ready to use the cluster**

At this step, you have completed the installation process and are ready to use the CitusDB cluster. You can now login to the master node and start executing commands. The command below, when run in the psql shell, should output the worker nodes mentioned in the pg_worker_list.conf.

::

	/opt/citusdb/4.0/bin/psql -h localhost -d postgres
	select * from master_get_active_worker_nodes();

To help you get started, we have an :ref:`examples_index` guide which has instructions on setting up a cluster with sample data in minutes. You can also visit the :ref:`user_guide_index` section of our documentation to learn about CitusDB commands in detail.


**8. Cluster notes**

The template automatically tunes the system configuration for CitusDB and sets up RAID on the SSD drives where appropriate, making it a great starting point even for production systems.

The database and its configuration files are stored in /data/base. So, to change any configuration parameters, you need to update the postgresql.conf file at /data/base/postgresql.conf.

Similarly to restart the database, you can use the command:

::

	/opt/citusdb/4.0/bin/pg_ctl -D /data/base -l logfile restart

Note: You typically want to avoid making changes to resources created by CloudFormation, such as terminating EC2 instances. To shut the cluster down, you can simply delete the stack in the CloudFormation console.
