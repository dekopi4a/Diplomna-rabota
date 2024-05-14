provider "aws" {
  region = "eu-central-1"
}

resource "aws_vpc" "david_vpc" {
  cidr_block = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = {
    Name = "david-vpc"
  }
}

resource "aws_subnet" "david_public_subnet" {
  vpc_id                  = aws_vpc.david_vpc.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "eu-central-1a"
  map_public_ip_on_launch = true
  tags = {
    Name = "david_public_subnet"
  }
}

resource "aws_subnet" "david_private_subnet" {
  vpc_id            = aws_vpc.david_vpc.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "eu-central-1b"
  tags = {
    Name = "david_private_subnet"
  }
}

resource "aws_subnet" "david_public_subnet_2" {
  vpc_id                  = aws_vpc.david_vpc.id
  cidr_block              = "10.0.4.0/24"
  availability_zone       = "eu-central-1c"
  map_public_ip_on_launch = true

  tags = {
    Name = "david_public_subnet_2"
  }
}


resource "aws_internet_gateway" "david_ig" {
  vpc_id = aws_vpc.david_vpc.id
  tags = {
    Name = "david_ig"
  }
}

resource "aws_eip" "nat_eip" {
  domain = "vpc" 
  tags = {
    Name = "david_nat_eip"
  }
}

resource "aws_nat_gateway" "david_ng" {
  allocation_id = aws_eip.nat_eip.id
  subnet_id     = aws_subnet.david_public_subnet.id
  tags = {
    Name = "david_ng"
  }
}

resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.david_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.david_ig.id
  }
  tags = {
    Name = "public_rt"
  }
}

resource "aws_route_table_association" "public_rta" {
  subnet_id      = aws_subnet.david_public_subnet.id
  route_table_id = aws_route_table.public_rt.id
}

resource "aws_route_table" "private_rt" {
  vpc_id = aws_vpc.david_vpc.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.david_ng.id
  }
  tags = {
    Name = "private_rt"
  }
}

resource "aws_route_table_association" "private_rta" {
  subnet_id      = aws_subnet.david_private_subnet.id
  route_table_id = aws_route_table.private_rt.id
}

resource "aws_security_group" "allow_all" {
  name        = "david-allow"
  description = "Allow all inbound and outbound traffic"
  vpc_id      = aws_vpc.david_vpc.id

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_efs_file_system" "efs" {
  creation_token = "efs_all"

  tags = {
    Name = "david-efs1"
  }
}

resource "aws_efs_file_system" "david_efs" {
  creation_token = "david_efs"

  tags = {
    Name = "david-efs"
  }
}

resource "aws_efs_access_point" "access_point" {
  file_system_id = aws_efs_file_system.efs.id

  root_directory {
    path = "/"
  }
  tags = {
    Name = "david-ap1"
  }
}

resource "aws_efs_access_point" "david_access_point" {
  file_system_id = aws_efs_file_system.david_efs.id

  root_directory {
    path = "/"
  }
  tags = {
    Name = "david-ap"
  }
}

resource "aws_efs_mount_target" "mount_target_1" {
  file_system_id  = aws_efs_file_system.efs.id
  subnet_id       = aws_subnet.david_private_subnet.id 
  security_groups = [aws_security_group.allow_all.id]  
}

resource "aws_efs_mount_target" "mount_target_2" {
  file_system_id  = aws_efs_file_system.efs.id
  subnet_id       = aws_subnet.david_public_subnet.id  
  security_groups = [aws_security_group.allow_all.id]  
}

resource "aws_efs_mount_target" "david_mount_target_1" {
  file_system_id  = aws_efs_file_system.david_efs.id
  subnet_id       = aws_subnet.david_private_subnet.id 
  security_groups = [aws_security_group.allow_all.id]  
}

resource "aws_efs_mount_target" "david_mount_target_2" {
  file_system_id  = aws_efs_file_system.david_efs.id
  subnet_id       = aws_subnet.david_public_subnet.id  
  security_groups = [aws_security_group.allow_all.id]  
}

resource "aws_ecs_task_definition" "david_task" {
  family                   = "david-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "2048"
  memory                   = "4096"

  container_definitions = jsonencode([
    {
      name      = "wordpress"
      image     = "wordpress"
      cpu       = 2
      essential = true
      portMappings = [
        {
          containerPort = 80
          hostPort      = 80
          protocol      = "tcp"
        },
      ]
      environment = [
        { name = "WORDPRESS_DB_USER", value = "david" },
        { name = "WORDPRESS_TABLE_CONFIG", value = "wp_" },
        { name = "ALLOW_EMPTY_PASSWORD", value = "yes" },
        { name = "WORDPRESS_DB_PASSWORD", value = var.WORDPRESS_DB_PASSWORD },
        { name = "WORDPRESS_DB_HOST", value = "david-database.cbfdjhqtfvrp.eu-central-1.rds.amazonaws.com" },
        { name = "WORDPRESS_DB_NAME", value = "tf_wp_david" },
        { name = "PHP_MEMORY_LIMIT", value = "512M" },
        { name = "enabled", value = "false" }
      ]
      mountPoints = [
        {
          sourceVolume  = "david_efs"
          containerPath = "/var/www/html"
        },
      ]
    },
  ])

  volume {
    name = "david_efs"

    efs_volume_configuration {
      file_system_id          = aws_efs_file_system.david_efs.id 
      root_directory          = "/"
      transit_encryption      = "ENABLED"
      authorization_config {
        access_point_id      = aws_efs_access_point.david_access_point.id 
        iam                  = "DISABLED"
      }
    }
  }
}

resource "aws_ecs_cluster" "cluster" {
  name = "tf_david_cluster"
}

resource "aws_iam_role" "ecs_execution_role" {
  name = "ecs_execution_role_1"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action = "sts:AssumeRole",
      Effect = "Allow",
      Principal = {
        Service = "ecs-tasks.amazonaws.com"
      }
    }]
  })
}

resource "aws_ecs_service" "wordpress_service" {
  name            = "wordpress"
  cluster         = aws_ecs_cluster.cluster.arn 
  task_definition = aws_ecs_task_definition.david_task.family 
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets         = [aws_subnet.david_public_subnet.id, aws_subnet.david_private_subnet.id, aws_subnet.david_public_subnet_2.id]
    security_groups = [aws_security_group.allow_all.id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.david_target_group.arn
    container_name   = "wordpress"
    container_port   = 80
  }

  depends_on = [
    aws_lb_listener.david_listener,
  ]
}

resource "aws_lb" "david_lb" {
  name               = "david-lb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.allow_all.id]
  subnets            = [aws_subnet.david_public_subnet.id, aws_subnet.david_public_subnet_2.id]

  enable_deletion_protection = false
}

resource "aws_lb_target_group" "david_target_group" {
  name     = "david-targetgroup"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.david_vpc.id
  target_type = "ip"

  health_check {
    healthy_threshold   = 3
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
    path                = "/var/www/html/index.php"
    protocol            = "HTTP"
    matcher             = "200,301,302"
  }
}

resource "aws_lb_listener" "david_listener" {
  load_balancer_arn = aws_lb.david_lb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.david_target_group.arn
  }
}

resource "aws_appautoscaling_target" "ecs_service" {
  service_namespace  = "ecs"
  resource_id        = "service/${aws_ecs_cluster.cluster.name}/${aws_ecs_service.wordpress_service.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  min_capacity       = 1
  max_capacity       = 3
}

resource "aws_appautoscaling_policy" "scale_out" {
  name               = "cpu-scale-out"
  service_namespace  = "ecs"
  resource_id        = aws_appautoscaling_target.ecs_service.resource_id
  scalable_dimension = "ecs:service:DesiredCount"
  policy_type        = "TargetTrackingScaling"
  target_tracking_scaling_policy_configuration {
    target_value       = 70.0
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
    scale_out_cooldown  = 60
    scale_in_cooldown   = 60
  }
}

resource "aws_appautoscaling_policy" "scale_in" {
  name               = "memory-scale-in"
  service_namespace  = "ecs"
  resource_id        = aws_appautoscaling_target.ecs_service.resource_id
  scalable_dimension = "ecs:service:DesiredCount"
  policy_type        = "TargetTrackingScaling"
  target_tracking_scaling_policy_configuration {
    target_value       = 30.0
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageMemoryUtilization"
    }
    scale_out_cooldown  = 60
    scale_in_cooldown   = 60
  }
}
