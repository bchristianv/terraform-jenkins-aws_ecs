# Outputs

output "load_balancer_dns_name" {
  value = aws_alb.jenkins_alb.dns_name
}

output "aws_region" {
  value = var.aws_region
}

output "ecs-cluster_name" {
  value = aws_ecs_cluster.ecs_cluster.name
}

output "ecs-cloud_tunnel_connection" {
  value = "${aws_service_discovery_service.jenkins_sd_service.name}.${aws_service_discovery_private_dns_namespace.jenkins_sd_ns.name}:50000"
}

output "jenkins_agent_security_group_id" {
  value = aws_security_group.sg_jenkins_agent.id
}

output "jenkins_execution_role_arn" {
  value = aws_iam_role.jenkins_execution_role.arn
}

output "jenkins_log_group" {
  value = aws_cloudwatch_log_group.lg_jenkins.name
}

output "jenkins_task_private_subnet_ids" {
  value = module.vpc.private_subnet_ids
}
