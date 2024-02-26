# Specify the provider and the AWS region
provider "aws" {
  region = "us-east-1"
}

# Create a VPC with CIDR block 10.0.0.0/16
resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
}

# Create a public subnet within the VPC with CIDR block 10.0.0.0/24
resource "aws_subnet" "public" {
  vpc_id     = aws_vpc.main.id
  cidr_block = "10.0.0.0/24"
}

# Create an Internet Gateway and attach it to the VPC
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
}

# Create a route table for the VPC and add routes to the Internet Gateway
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  # Route for IPv4 traffic
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  # Route for IPv6 traffic
  route {
    ipv6_cidr_block = "::/0"
    gateway_id      = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "public"
  }
}

# Create a security group within the VPC
resource "aws_security_group" "sg" {
  name   = "sg"
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

# Create an EC2 instance within the public subnet
resource "aws_instance" "web" {
  ami           = "ami-0c7217cdde317cfec" # This is an example Amazon Linux 2 AMI ID. Replace with the AMI ID you want to use.
  instance_type = "t2.micro"
  subnet_id     = aws_subnet.public.id
  key_name      = "vockey" # Replace with your key pair name

  vpc_security_group_ids = [aws_security_group.sg.id]

  # User data to install and start Apache on the instance
  user_data = <<-EOF
              #!/bin/bash
              yum update -y
              yum install -y httpd
              systemctl start httpd
              systemctl enable httpd
              echo "Hello, World" > /var/www/html/index.html
              EOF

  tags = {
    Name = "web"
  }
}