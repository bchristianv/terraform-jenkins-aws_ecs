# Jenkins AWS ECS

data "aws_caller_identity" "current" {}

# Optionally use a data resource to reference an existing vpc and/or
# ecs cluster and update the module resource references throughout
module "vpc" {
  source = "github.com/bchristianv/terraform_mod-aws_vpc?ref=1.1.2"

  aws_region = var.aws_region

  az_private_subnets      = var.vpc-az_private_subnets
  az_public_subnets       = var.vpc-az_public_subnets
  cidr                    = var.vpc-cidr
  internal_dns_domainname = var.vpc-internal_dns_domainname
  name                    = var.vpc-name
  tags                    = var.vpc-tags
}

resource "aws_ecs_cluster" "ecs_cluster" {
  name = var.ecs-cluster_name
  tags = merge(
    var.ecs-tags,
    { "Name" = var.ecs-cluster_name }
  )
}

resource "aws_cloudwatch_log_group" "lg_jenkins" {
  name              = "ECSLogGroup-${var.ecs-cluster_name}-jenkins"
  retention_in_days = 14
  tags              = var.ecs-app_tags
}

resource "aws_security_group" "sg_jenkins" {
  name        = "JenkinsSecurityGroup"
  description = "Enable Jenkins access"
  vpc_id      = module.vpc.id
  tags        = var.ecs-app_tags
}

resource "aws_security_group_rule" "tcp8080_lb_inbound" {
  type                     = "ingress"
  from_port                = 8080
  to_port                  = 8080
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.sg_jenkins_lb.id
  security_group_id        = aws_security_group.sg_jenkins.id
  description              = "Allow Jenkins Load Balancer tcp 8080 inbound"
}

resource "aws_security_group_rule" "tcp8080_agent_inbound" {
  type                     = "ingress"
  from_port                = 8080
  to_port                  = 8080
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.sg_jenkins_agent.id
  security_group_id        = aws_security_group.sg_jenkins.id
  description              = "Allow Jenkins agent tcp 8080 inbound"
}

resource "aws_security_group_rule" "tcp50000_agentinbound" {
  type                     = "ingress"
  from_port                = 50000
  to_port                  = 50000
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.sg_jenkins_agent.id
  security_group_id        = aws_security_group.sg_jenkins.id
  description              = "Allow Jenkins agent tcp 50000 inbound"
}

resource "aws_security_group_rule" "all_outbound" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.sg_jenkins.id
  description       = "Allow Jenkins all outbound"
}

resource "aws_security_group" "sg_jenkins_agent" {
  name        = "JenkinsAgentSecurityGroup"
  description = "Enable Jenkins agent access"
  vpc_id      = module.vpc.id
  egress {
    description = "Allow Jenkins agent all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = var.ecs-app_tags
}

resource "aws_security_group" "sg_efs" {
  name        = "EFSSecurityGroup"
  description = "Enable EFS access"
  vpc_id      = module.vpc.id
  ingress {
    description     = "Allow EFS tcp 2049 inbound"
    from_port       = 2049
    to_port         = 2049
    protocol        = "tcp"
    security_groups = [aws_security_group.sg_jenkins.id]
  }
  egress {
    description = "Allow EFS all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [module.vpc.cidr_block]
  }
  tags = var.ecs-app_tags
}

resource "aws_security_group" "sg_jenkins_lb" {
  name        = "JenkinsLoadBalancerSecurityGroup"
  description = "Enable Jenkins HTTPS access via load balancer"
  vpc_id      = module.vpc.id
  ingress {
    description = "Allow https inbound"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = var.jenkins_source_cidrs
  }
  egress {
    description     = "Allow 8080 outbound"
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.sg_jenkins.id]
  }
  tags = var.ecs-app_tags
}

resource "aws_efs_file_system" "jenkins_home_fs" {
  encrypted = true
  tags = merge(
    var.ecs-app_tags,
    { "Name" = "jenkins-home" }
  )
}

resource "aws_efs_mount_target" "jenkins_home_mt" {
  count           = length(module.vpc.private_subnet_ids)
  file_system_id  = aws_efs_file_system.jenkins_home_fs.id
  subnet_id       = module.vpc.private_subnet_ids[count.index]
  security_groups = [aws_security_group.sg_efs.id]
}

resource "aws_efs_access_point" "jenkins_home_ap" {
  file_system_id = aws_efs_file_system.jenkins_home_fs.id
  posix_user {
    uid = 1000
    gid = 1000
  }
  root_directory {
    creation_info {
      owner_uid   = 1000
      owner_gid   = 1000
      permissions = "755"
    }
    path = "/jenkins-home"
  }
  tags = var.ecs-app_tags
}

resource "aws_iam_role" "jenkins_role" {
  name               = "jenkins-role"
  description        = "Jenkins ECS task role"
  path               = "/"
  assume_role_policy = <<EOT
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "ecs-tasks.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOT
  tags               = var.ecs-app_tags
}

resource "aws_iam_policy" "efs_write_policy" {
  name        = "root"
  description = "Mount and write EFS"
  path        = "/"
  policy      = <<EOT
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "elasticfilesystem:ClientMount",
        "elasticfilesystem:ClientWrite"
      ],
      "Effect": "Allow",
      "Resource": "arn:aws:elasticfilesystem:${var.aws_region}:${data.aws_caller_identity.current.account_id}:file-system/${aws_efs_file_system.jenkins_home_fs.id}"
    }
  ]
}
EOT
}

resource "aws_iam_role_policy_attachment" "task_role_policy1" {
  role       = aws_iam_role.jenkins_role.name
  policy_arn = aws_iam_policy.efs_write_policy.arn
}

resource "aws_iam_policy" "create_jenkins_agents" {
  name        = "create-jenkins-agents"
  description = "Create Jenkins agents"
  path        = "/"
  policy      = <<EOT
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "ecs:RegisterTaskDefinition",
        "ecs:ListClusters",
        "ecs:DescribeContainerInstances",
        "ecs:ListTaskDefinitions",
        "ecs:DescribeTaskDefinition",
        "ecs:DeregisterTaskDefinition"
      ],
      "Effect": "Allow",
      "Resource": "*"
    },
    {
      "Action": [
        "ecs:ListContainerInstances"
      ],
      "Effect": "Allow",
      "Resource": "arn:aws:ecs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:cluster/${var.ecs-cluster_name}"
    },
    {
      "Action": [
        "ecs:RunTask"
      ],
      "Effect": "Allow",
      "Condition": {
        "ArnEquals": {
          "ecs:cluster": "arn:aws:ecs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:cluster/${var.ecs-cluster_name}"
        }
      },
      "Resource": "arn:aws:ecs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:task-definition/*"
    },
    {
      "Action": [
        "ecs:StopTask"
      ],
      "Effect": "Allow",
      "Condition": {
        "ArnEquals": {
          "ecs:cluster": "arn:aws:ecs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:cluster/${var.ecs-cluster_name}"
        }
      },
      "Resource": "arn:aws:ecs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:task/*"
    },
    {
      "Action": [
        "ecs:DescribeTasks"
      ],
      "Effect": "Allow",
      "Condition": {
        "ArnEquals": {
          "ecs:cluster": "arn:aws:ecs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:cluster/${var.ecs-cluster_name}"
        }
      },
      "Resource": "arn:aws:ecs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:task/*"
    },
    {
      "Action": [
        "iam:GetRole",
        "iam:PassRole"
      ],
      "Effect": "Allow",
      "Resource": "${aws_iam_role.jenkins_execution_role.arn}"
    }
  ]
}
EOT
}

resource "aws_iam_role_policy_attachment" "task_role_policy2" {
  role       = aws_iam_role.jenkins_role.name
  policy_arn = aws_iam_policy.create_jenkins_agents.arn
}

resource "aws_iam_role" "jenkins_execution_role" {
  name               = "jenkins-execution-role"
  description        = "Jenkins ECS task execution role"
  path               = "/"
  assume_role_policy = <<EOT
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "ecs-tasks.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOT
  tags               = var.ecs-app_tags
}

resource "aws_iam_role_policy_attachment" "jenkins_execution_role_policy" {
  role       = aws_iam_role.jenkins_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_ecs_task_definition" "jenkins-task" {
  family             = "jenkins-task"
  cpu                = 512
  memory             = 1024
  network_mode       = "awsvpc"
  task_role_arn      = aws_iam_role.jenkins_role.arn
  execution_role_arn = aws_iam_role.jenkins_execution_role.arn
  requires_compatibilities = [
    "FARGATE",
    "EC2"
  ]
  container_definitions = templatefile(
    "task-definitions/jenkins.json", {
      awslogs_group  = aws_cloudwatch_log_group.lg_jenkins.name,
      awslogs_region = var.aws_region
      docker_image   = var.jenkins_docker_image
    }
  )
  volume {
    name = "jenkins-home"
    efs_volume_configuration {
      file_system_id     = aws_efs_file_system.jenkins_home_fs.id
      transit_encryption = "ENABLED"
      authorization_config {
        access_point_id = aws_efs_access_point.jenkins_home_ap.id
        iam             = "ENABLED"
      }
    }
  }
  tags = var.ecs-app_tags
}

resource "aws_alb_target_group" "jenkins_alb_tg" {
  name                 = "JenkinsTargetGroup"
  port                 = 8080
  protocol             = "HTTP"
  vpc_id               = module.vpc.id
  target_type          = "ip"
  deregistration_delay = 10
  health_check {
    path    = "/login"
    matcher = "200"
  }
  tags = var.ecs-app_tags
}

resource "aws_alb" "jenkins_alb" {
  name            = "jenkins"
  subnets         = module.vpc.public_subnet_ids
  security_groups = [aws_security_group.sg_jenkins_lb.id]
  tags            = var.ecs-app_tags
}

resource "aws_alb_listener" "jenkins_alb_listener" {
  load_balancer_arn = aws_alb.jenkins_alb.arn
  port              = 443
  protocol          = "HTTPS"
  certificate_arn   = var.certificate_arn
  default_action {
    type             = "forward"
    target_group_arn = aws_alb_target_group.jenkins_alb_tg.arn
  }
}

resource "aws_service_discovery_private_dns_namespace" "jenkins_sd_ns" {
  name        = "jenkins-sd-namespace"
  description = "Jenkins service discovery namespace"
  vpc         = module.vpc.id
  tags        = var.ecs-app_tags
}

resource "aws_service_discovery_service" "jenkins_sd_service" {
  name         = "jenkins"
  namespace_id = aws_service_discovery_private_dns_namespace.jenkins_sd_ns.id
  dns_config {
    namespace_id = aws_service_discovery_private_dns_namespace.jenkins_sd_ns.id
    dns_records {
      ttl  = 60
      type = "A"
    }
    dns_records {
      ttl  = 60
      type = "SRV"
    }
    routing_policy = "MULTIVALUE"
  }
  tags = var.ecs-app_tags
}

resource "aws_ecs_service" "jenkins-service" {
  name                               = "Jenkins-ECS_service"
  cluster                            = aws_ecs_cluster.ecs_cluster.id
  task_definition                    = aws_ecs_task_definition.jenkins-task.arn
  desired_count                      = 1
  health_check_grace_period_seconds  = 300
  launch_type                        = "FARGATE"
  platform_version                   = "1.4.0"
  deployment_minimum_healthy_percent = 0
  deployment_maximum_percent         = 100
  network_configuration {
    assign_public_ip = false
    subnets          = module.vpc.private_subnet_ids
    security_groups  = [aws_security_group.sg_jenkins.id]
  }
  load_balancer {
    container_name   = "jenkins"
    container_port   = 8080
    target_group_arn = aws_alb_target_group.jenkins_alb_tg.arn
  }
  service_registries {
    registry_arn = aws_service_discovery_service.jenkins_sd_service.arn
    port         = 50000
  }
  depends_on = [aws_alb_listener.jenkins_alb_listener]
}
