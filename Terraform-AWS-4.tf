# Create a new workspace called dev
# terraform {
#   workspace "dev"
# }

# Specify the provider and the AWS region
provider "aws" {
  region = "us-east-1"
}

# Create a VPC with CIDR block 10.0.0.0/16
resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
}

# Create 2 public subnets within the VPC with CIDR block 10.0.0.0/24 and 10.0.2.0/24
resource "aws_subnet" "public" {
  count             = 2
  vpc_id            = aws_vpc.main.id
  cidr_block        = element(["10.0.0.0/24", "10.0.2.0/24"], count.index)
  availability_zone = element(["us-east-1a", "us-east-1b"], count.index)
}

# Create 2 private subnets within the VPC with CIDR block 10.0.1.0/24 and 10.0.3.0/24
resource "aws_subnet" "private" {
  count             = 2
  vpc_id            = aws_vpc.main.id
  cidr_block        = element(["10.0.1.0/24", "10.0.3.0/24"], count.index)
  availability_zone = element(["us-east-1a", "us-east-1b"], count.index)
}

# Create a route table for the VPC and add routes to the Internet Gateway
resource "aws_route_table" "main" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
}

# Create a security group within the VPC
resource "aws_security_group" "main" {
  name   = "main-sg"
  vpc_id = aws_vpc.main.id

  # Allow incoming HTTP traffic
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow all outgoing traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Install NGINX on the 2 public subnets and APACHE on the 2 private subnets
# Provision NGINX using user_data script

variable "key_name" {
  type    = string
  default = "default_key_name"
}

resource "aws_instance" "nginx" {
  count         = 2
  ami           = data.aws_ami.nginx_ami.id
  instance_type = "t2.micro"
  subnet_id     = element(aws_subnet.public.*.id, count.index)
  key_name      = var.key_name

  user_data = <<-EOF
              #!/bin/bash
              yum update -y
              yum install -y nginx
              systemctl start nginx
              systemctl enable nginx
              EOF

  tags = {
    Name = "nginx-${count.index}"
  }
}

# Provision Apache using remote-exec and local-exec provisioners
resource "aws_instance" "apache" {
  count         = 2
  ami           = data.aws_ami.apache_ami.id
  instance_type = "t2.micro"
  subnet_id     = element(aws_subnet.private.*.id, count.index)
  key_name      = var.key_name

  provisioner "remote-exec" {
    inline = [
      "sudo yum update -y",
      "sudo yum install -y httpd",
      "sudo systemctl start httpd",
      "sudo systemctl enable httpd"
    ]
  }

  provisioner "local-exec" {
    command = <<-EOT
      echo "public-ip${count.index} ${aws_instance.apache[count.index].public_ip}" >> all-ips.txt
      echo "private-ip${count.index} ${aws_instance.apache[count.index].private_ip}" >> all-ips.txt
    EOT
  }

  tags = {
    Name = "apache-${count.index}"
  }
}

# Attach Internet Gateway with a public load balancer that attaches to the 2 public subnets
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
}

resource "aws_lb" "public_lb" {
  name               = "public-lb"
  internal           = false
  load_balancer_type = "application"
  subnets            = aws_subnet.public[*].id
}

# Create a load balancer that gets traffic from NGINX on the 2 public subnets and sends traffic to APACHE on the 2 private subnets
resource "aws_lb_target_group" "nginx_target_group" {
  name     = "nginx-target-group"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id

  health_check {
    interval            = 30
    path                = "/"
    protocol            = "HTTP"
    timeout             = 10
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }
}

resource "aws_lb_target_group" "apache_target_group" {
  name   = "apache-target-group"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id

  health_check {
    interval            = 30
    path                = "/"
    protocol            = "HTTP"
    timeout             = 10
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }
}

resource "aws_lb_listener" "nginx_listener" {
  load_balancer_arn = aws_lb.public_lb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.nginx_target_group.arn
  }
}

resource "aws_lb_listener" "apache_listener" {
  load_balancer_arn = aws_lb.public_lb.arn
  port              = 8080
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.apache_target_group.arn
  }
}

# Create a remote bucket for statefile
resource "aws_s3_bucket" "terraform_state" {
  bucket = "terraform-state-bucket"
  acl    = "private"
}

# Output the statefile bucket name
output "terraform_state_bucket_name" {
  value = aws_s3_bucket.terraform_state.bucket
}

# Use the datasource to get the image ID for ec2
data "aws_ami" "nginx_ami" {
  most_recent = true

  filter {
    name   = "name"
    values = ["nginx-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["amazon"]
}

data "aws_ami" "apache_ami" {
  most_recent = true

  filter {
    name   = "name"
    values = ["apache-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["amazon"]
}

