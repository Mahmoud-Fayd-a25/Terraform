provider "aws" {
  region = "us-east-1"  
}

resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
}

resource "aws_subnet" "public" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.0.0/24"
  availability_zone = "us-east-1a"

  map_public_ip_on_launch = true
}

resource "aws_subnet" "private" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "us-east-1b"
}

resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main.id
}

resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.main.id
}

resource "aws_route_table_association" "public_route_association" {
  route_table_id = aws_route_table.public_route_table.id
  subnet_id      = aws_subnet.public.id
}

resource "aws_route" "public_route" {
  route_table_id         = aws_route_table.public_route_table.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.gw.id
}

resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public.id
}

resource "aws_eip" "nat" {
  network_interface = aws_nat_gateway.nat.network_interface_ids[0]
}

resource "aws_route_table" "private_route_table" {
  vpc_id = aws_vpc.main.id
}

resource "aws_subnet_association" "private_subnet_association" {
  subnet_id      = aws_subnet.private.id
  route_table_id = aws_route_table.private_route_table.id
}

resource "aws_route" "private_route" {
  route_table_id         = aws_route_table.private_route_table.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.nat.id
}

# Security groups
resource "aws_security_group" "web_server_sg" {
  name        = "web_server_sg"
  vpc_id      = aws_vpc.main.id
  description = "Security group for web servers"

ingress {
    from_port = 80  
    to_port   = 80
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]  
  }

  egress {
    from_port = 0
    to_port   = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]  
  }
}

resource "aws_security_group" "backend_server_sg" {
  name        = "backend_server_sg"
  vpc_id      = aws_vpc.main.id
  description = "Security group for backend servers"

ingress {
    from_port = 80  
    to_port   = 80
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]  
  }

  egress {
    from_port = 0
    to_port   = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]  
  }
}

resource "aws_instance" "web_server" {
  ami                    = "ami-0123456789abcdef0"  
  instance_type          = "t2.micro"
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.web_server_sg.id]

}

resource "aws_instance" "backend_server" {
  ami                    = "ami-0123456789abcdef0"  
  instance_type          = "t2.micro"
  subnet_id              = aws_subnet.private.id
  vpc_security_group_ids = [aws_security_group.backend_server_sg.id]

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
