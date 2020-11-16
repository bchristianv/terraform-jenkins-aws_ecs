# Outputs

output "load_balancer_dns_name" {
  value = aws_alb.jenkins_alb.dns_name
}
