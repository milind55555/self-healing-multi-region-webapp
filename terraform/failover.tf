data "archive_file" "failover" {
  type = "zip"
  source_file = "${path.module}/../lambda/failover.py"
  output_path = "${path.module}/failover.zip"
}
resource "aws_iam_role" "lambda_role" {
  provider = aws.primary
  name = "shmr-route53-failover-lambda"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{ Effect = "Allow", Principal = { Service = "lambda.amazonaws.com" }, Action = "sts:AssumeRole" }]
  })
}
resource "aws_iam_role_policy_attachment" "lambda_logs" {
  provider = aws.primary
  role = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}
resource "aws_iam_role_policy" "route53" {
  provider = aws.primary
  role = aws_iam_role.lambda_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = ["route53:ChangeResourceRecordSets"]
      Resource = "arn:aws:route53:::hostedzone/${var.hosted_zone_id}"
    }]
  })
}
resource "aws_lambda_function" "failover" {
  provider = aws.primary
  function_name = "shmr-route53-failover"
  role = aws_iam_role.lambda_role.arn
  runtime = "python3.12"
  handler = "failover.lambda_handler"
  filename = data.archive_file.failover.output_path
  source_code_hash = data.archive_file.failover.output_base64sha256
  timeout = 30
  environment {
    variables = {
      HOSTED_ZONE_ID = var.hosted_zone_id
      RECORD_NAME = var.app_fqdn
      PRIMARY_DNS = var.primary_lb_dns
      SECONDARY_DNS = var.secondary_lb_dns
      TTL = "30"
    }
  }
}
resource "aws_sns_topic" "failover" {
  provider = aws.primary
  name = "shmr-failover-events"
}
resource "aws_lambda_permission" "allow_sns" {
  provider = aws.primary
  statement_id = "AllowExecutionFromSNS"
  action = "lambda:InvokeFunction"
  function_name = aws_lambda_function.failover.function_name
  principal = "sns.amazonaws.com"
  source_arn = aws_sns_topic.failover.arn
}
resource "aws_sns_topic_subscription" "lambda" {
  provider = aws.primary
  topic_arn = aws_sns_topic.failover.arn
  protocol = "lambda"
  endpoint = aws_lambda_function.failover.arn
  depends_on = [aws_lambda_permission.allow_sns]
}
resource "aws_cloudwatch_metric_alarm" "primary_unhealthy" {
  provider = aws.primary
  alarm_name = "shmr-primary-unhealthy"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods = 2
  metric_name = "HealthyHostCount"
  namespace = "AWS/ApplicationELB"
  period = 60
  statistic = "Minimum"
  threshold = 0
  alarm_description = "Trigger regional failover when primary ALB has no healthy targets."
  alarm_actions = [aws_sns_topic.failover.arn]
  ok_actions = [aws_sns_topic.failover.arn]
  treat_missing_data = "breaching"
  dimensions = { LoadBalancer = var.primary_lb_dimension, TargetGroup = var.primary_target_group_dimension }
}
