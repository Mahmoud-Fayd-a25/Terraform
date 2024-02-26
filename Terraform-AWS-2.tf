# provisions a highly available web application environment with an Elastic Load Balancer, Auto Scaling Group, and Launch Configuration.
# It also configures security groups, subnets, and routing in the VPC

# Specify the provider and the AWS region
provider "aws" {
  region = "us-east-1"
}

# Create a VPC with CIDR block 10.0.0.0/16
resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support = true
}

# Create a public subnet within the VPC with CIDR block 10.0.0.0/24
resource "aws_subnet" "public" {
  vpc_id     = aws_vpc.main.id
  cidr_block = "10.0.0.0/24"
  map_public_ip_on_launch = true
}

# Create an Internet Gateway and attach it to the VPC
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
}

# Create a route table for the VPC and add routes to the Internet Gateway
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "public"
  }
}

# Create a security group for the web servers
resource "aws_security_group" "web_sg" {
  name   = "web_sg"
  vpc_id = aws_vpc.main.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Create an Elastic Load Balancer
resource "aws_elb" "web_lb" {
  name               = "web_lb"
  availability_zones = ["us-east-1a", "us-east-1b"]
  security_groups    = [aws_security_group.web_sg.id]
  subnets            = [aws_subnet.public.id]

  listener {
    instance_port      = 80
    instance_protocol  = "HTTP"
    lb_port            = 80
    lb_protocol        = "HTTP"
  }

  health_check {
    target              = "HTTP:80/"
    interval            = 30
    timeout             = 5
    unhealthy_threshold = 2
    healthy_threshold   = 2
  }
}

# Create Auto Scaling Group
resource "aws_autoscaling_group" "web_asg" {
  launch_configuration = aws_launch_configuration.web_lc.name
  min_size              = 2
  max_size              = 5
  desired_capacity      = 3
  availability_zones    = ["us-east-1a", "us-east-1b"]

  tag {
    key                 = "Name"
    value               = "web_instance"
    propagate_at_launch = true
  }
}

# Create Launch Configuration
resource "aws_launch_configuration" "web_lc" {
  name                 = "web_lc"
  image_id             = "ami-0c55b159cbfafe1f0"
  instance_type        = "t2.micro"
  security_groups      = [aws_security_group.web_sg.name]
  key_name             = "my_key_pair"
  user_data            = <<-EOF
                          #!/bin/bash
                          yum update -y
                          yum install -y httpd
                          systemctl start httpd
                          systemctl enable httpd
                          echo "Hello, World!" > /var/www/html/index.html
                          EOF
}
