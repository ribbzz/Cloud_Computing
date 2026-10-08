"""Create the two demo accounts required by the brief (>= 2 roles).

Run once, from inside the api container:
    docker compose exec api python seed_users.py

Passwords are read from the environment so that no credential is ever
written into the image, the repository, or the shell history file.
"""
import os
import sys

import boto3

from main import hash_password  # reuse the exact hashing used at login

REGION = os.environ.get("AWS_REGION", "eu-west-3")
USERS_TABLE = os.environ.get("USERS_TABLE", "campuspulse-users")

USERS = [
    # username env var           role      description
    ("ADMIN_USER", "ADMIN_PASSWORD", "admin",
     "campus operations manager - can read /alerts"),
    ("STAFF_USER", "STAFF_PASSWORD", "staff",
     "front desk staff - dashboard and stats only"),
    ("DEVICE_USER", "DEVICE_PASSWORD", "device",
     "sensor fleet identity - can only POST /events"),
]

def main() -> int:
    table = boto3.resource("dynamodb", region_name=REGION).Table(USERS_TABLE)
    for user_var, pass_var, role, description in USERS:
        username = os.environ.get(user_var)
        password = os.environ.get(pass_var)
        if not username or not password:
            print(f"skip {role}: set {user_var} and {pass_var}")
            continue
        table.put_item(Item={
            "username": username,
            "password_hash": hash_password(password),
            "role": role,
            "description": description,
        })
        print(f"seeded {username} with role {role}")
    return 0

if __name__ == "__main__":
    sys.exit(main())
