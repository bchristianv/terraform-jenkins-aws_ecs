# terraform-jenkins-aws_ecs
Terraform configuration to deploy Jenkins into AWS ECS/Fargate

## Setup
### Jenkins Master
After the stack has been created, the load balancer DNS name will be output as `load_balancer_dns_name`. Create a CNAME record in your DNS that points to the `load_balancer_dns_name` output.

The Jenkins admin password will be printed in the logs the first time Jenkins starts up and can be obtained by navigating to the Jenkins ECS Task and clicking on the Logs tab.

### Jenkins Slaves
Install the `amazon-ecs` Jenkins plugin. Navigate to Manage Jenkins > Manage Plugins > Available and search for `amazon-ecs`. If there are multiple search results select the plugin named Amazon Elastic Container Service (ECS) / Fargate, then click Install without restart.

#### Configuring an ECS cloud

Create a Jenkins cloud configuration so the master can spawn slaves in ECS to run jobs. Navigate to Manage Jenkins > Manage Nodes and Clouds > Configure Clouds. Click on Add a new cloud, select Amazon EC2 Container Service Cloud.

Enter the following values in the form to enable AWS access for Jenkins:

Name:	                `ecs-cloud`  
Amazon ECS Region Name:	`output.aws_region`  
ECS Cluster:	        `output.ecs-cluster_name`  

Click Advanced  
Tunnel connection through: `output.ecs-cloud_tunnel_connection`

Click the Add button next to ECS agent templates to define a template for Jenkins slave ECS tasks.

Label:	`ecs` # Used in pipeline definitions to select the slave agent  
Template Name: `jenkins-agent` # Will form part of the task definition name  
Docker Image: `jenkins/inbound-agent:alpine`  
Launch type: `FARGATE` # Fargate doesn't require provisioning of EC2 instances  
Soft Memory Reservation: `2048`	# See Supported Configurations for Fargate  
CPU units: `1024` # See Supported Configurations for Fargate  
Subnets: `output.jenkins_task_private_subnet_ids` # separated by comma  
Security Groups: `output.jenkins_agent_security_group_id`  
Click Advanced  
Task Execution Role ARN: `output.jenkins_execution_role_arn`  
Logging Driver: `awslogs`	
Logging Configuration:  Name/Value pairs configure Jenkins slave logs to be written to AWS CloudWatch  
awslogs-group: `output.jenkins_log_group`  
awslogs-region: `output.aws_region`  
awslogs-stream-prefix: `jenkins-agent`  
Click Save

#### Configuring a slave job
- Pipelines should be configured to run on an agent with the `ecs` label, matching the `Label` field in the ECS agent template configuration.

TODO:
- automated EFS backups via AWS Backup. Terraform AWS provider 3.16.0 currently does not support (11/2020)
