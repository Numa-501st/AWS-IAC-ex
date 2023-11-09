# Defining CIDR Block for VPC
variable "sme_vpc_cidr" {
  default = "10.0.0.0/16"
}
# Defining CIDR Block for 1st Public Subnet
variable "public_subnet1_cidr" {
  default = "10.0.0.0/20"
}

# Defining CIDR Block for 1st Private Subnet
variable "private_subnet1_cidr" {
  default = "10.0.32.0/20"
}
# Defining CIDR Block for 2nd Private Subnet
variable "private_subnet2_cidr" {
  default = "10.0.48.0/20"
}

## vpc

resource "aws_vpc" "sme_vpc" {
  cidr_block       = "${var.sme_vpc_cidr}"
  instance_tenancy = "default" 
  tags = {
    Name = "SME VPC"
  }
}


# S3 BUCKET
resource "aws_s3_bucket" "my_bucket" {
  bucket = "smebucket1323q"  

  acl    = "private"

  versioning {
    enabled = true  # Enable versioning for the bucket
  }

  tags = {
    Name        = "MyS3Bucket"
    Environment = "Production"
  }
}



# Creating Public Subnet 1
resource "aws_subnet" "public-subnet-1" {
  vpc_id                  = aws_vpc.sme_vpc.id
  cidr_block             = var.public_subnet1_cidr
  map_public_ip_on_launch = true
  availability_zone = "us-east-1a"

  tags = {
    Name = "Public Subnet 1"
  }
}


# Creating 1st EC2 instance in Public Subnet
resource "aws_instance" "sme_instance" {
  ami                         = "ami-01bc990364452ab3e"
  instance_type               = "t2.micro"
  vpc_security_group_ids      = ["${aws_security_group.sme_sg.id}"]
  subnet_id                   = "${aws_subnet.public-subnet-1.id}"
  associate_public_ip_address = true
  user_data                   = "${file("userdata.sh")}"
tags = {
    Name = "My Public SME Instance"
  }
}

# Creating Private Subnet 1 
resource "aws_subnet" "private-subnet-1" {
  vpc_id                  = aws_vpc.sme_vpc.id
  cidr_block             = var.private_subnet1_cidr
  map_public_ip_on_launch = false
  availability_zone       = "us-east-1a"

  tags = {
    Name = "Private Subnet 1"
  }
}

# Creating Private Subnet 2  
resource "aws_subnet" "private-subnet-2" {
  vpc_id                  = aws_vpc.sme_vpc.id
  cidr_block             = var.private_subnet2_cidr
  map_public_ip_on_launch = false
  availability_zone       = "us-east-1b"

  tags = {
    Name = "Private Subnet 2"
  }
}


### Public route table

resource "aws_route_table" "sme_route" {
    vpc_id = "${aws_vpc.sme_vpc.id}"
route {
        cidr_block = "0.0.0.0/0"
        gateway_id = "${aws_internet_gateway.sme_igw.id}"
    }
tags = {
        Name = "Route table"
    }
}
# Associating Route Table
resource "aws_route_table_association" "sme_route1" {
    subnet_id = "${aws_subnet.public-subnet-1.id}"
    route_table_id = "${aws_route_table.sme_route.id}"
}




# Creating Security Group 
resource "aws_security_group" "sme_sg" {
  vpc_id = "${aws_vpc.sme_vpc.id}"
# Inbound Rules
  # HTTP access from anywhere
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
# HTTPS access from anywhere
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
# SSH access from anywhere
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
# Outbound Rules
  # Internet access to anywhere
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
tags = {
    Name = "Web Security Group"
  }
}

# Create Elastic File System (EFS)
resource "aws_efs_file_system" "my_efs" {
  creation_token = "my-efs" 
  performance_mode = "generalPurpose"
  throughput_mode = "bursting"
  encrypted = false 

  tags = {
    Name = "MyEFS"
    Environment = "Production"
  }
}

# Create mount my_efs_mount_target
resource "aws_efs_mount_target" "my_efs_mount_target" {
  file_system_id = aws_efs_file_system.my_efs.id
  subnet_id      = aws_subnet.private-subnet-1.id
  security_groups = [aws_security_group.sme_sg.id] 
}


# Create Database Security Group
resource "aws_security_group" "sme_db_sg" {
  name        = "Database Security Group"
  description = "Allow inbound traffic from application layer"
  vpc_id      = aws_vpc.sme_vpc.id 
ingress {
    description     = "Allow traffic from application layer"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.sme_sg.id]
  }
egress {
    from_port   = 32768
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
tags = {
    Name = "Database Security Group"
  }
}


# Creating Internet Gateway 
resource "aws_internet_gateway" "sme_igw" {
  vpc_id = "${aws_vpc.sme_vpc.id}"
}


# Creating RDS Instance
resource "aws_db_subnet_group" "sme" {
  name       = "main"
  subnet_ids = [aws_subnet.private-subnet-1.id, aws_subnet.private-subnet-2.id]
tags = {
    Name = "My DB subnet group"
  }
}
resource "aws_db_instance" "default" {
  allocated_storage      = 100
  db_subnet_group_name   = aws_db_subnet_group.sme.id
  engine                 = "oracle-se2"
  instance_class         = "db.t3.large"
  multi_az               = true
  username               = "SME6"
  password               = "SME6"
  license_model          = "license-included"
  vpc_security_group_ids = [aws_security_group.sme_db_sg.id]
}


resource "aws_security_group" "elb_sg" {
  vpc_id = aws_vpc.sme_vpc.id

}

# Create an Elastic Load Balancer
resource "aws_elb" "my_elb" {
  name               = "my-elb"
  security_groups    = [aws_security_group.sme_sg.id]
  subnets            = [aws_subnet.public-subnet-1.id] 

  listener {
    instance_port     = 80
    instance_protocol = "http"
    lb_port           = 80
    lb_protocol       = "http"
  }

  health_check {
    target              = "HTTP:80/"
    interval            = 30
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 5
  }

  tags = {
    Name = "MyELB"
  }
}


# Create a Launch Configuration Security Group
resource "aws_security_group" "launch_config_security_group" {
  vpc_id = aws_vpc.sme_vpc.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Create a Launch Configuration
resource "aws_launch_configuration" "my_launch_config" {
  name_prefix                 = "my-launch-config-"
  image_id                    = "ami-01bc990364452ab3e"  
  instance_type               = "t2.micro"                
  security_groups             = [aws_security_group.sme_sg.id] 

  lifecycle {
    create_before_destroy = true
  }
}




# Create an Auto Scaling Group
resource "aws_autoscaling_group" "my_asg" {
  desired_capacity     = 2  # Number of instances to launch initially
  max_size            = 5  # Maximum number of instances in the ASG
  min_size            = 1  # Minimum number of instances in the ASG
  launch_configuration = aws_launch_configuration.my_launch_config.name
  vpc_zone_identifier  = [aws_subnet.private-subnet-1.id, aws_subnet.private-subnet-2.id]  

  tag {
    key                 = "Name"
    value               = "MyASGInstance"
    propagate_at_launch = true
  }

  depends_on = [aws_elb.my_elb]
}


# Create a NAT Gateway
resource "aws_nat_gateway" "my_nat_gateway" {
  allocation_id = aws_eip.nat_eip.id
  subnet_id     = aws_subnet.public-subnet-1.id 
}

# Allocate an Elastic IP for the NAT Gateway
resource "aws_eip" "nat_eip" {
  vpc = true
}



