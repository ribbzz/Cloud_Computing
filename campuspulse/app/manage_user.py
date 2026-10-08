"""Create or reset a demo account interactively without printing its password."""
import argparse
from getpass import getpass

from main import hash_password, users_table, verify_password


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("username")
    parser.add_argument("--role", required=True, choices=("admin", "staff", "device"))
    parser.add_argument("--create", action="store_true", help="Create only if absent")
    args = parser.parse_args()
    key = {"username": args.username}
    item = users_table.get_item(Key=key, ConsistentRead=True).get("Item")
    if args.create:
        if item is not None:
            parser.error("Account exists; omit --create to reset its password")
        item = {**key, "role": args.role}
        condition = {"ConditionExpression": "attribute_not_exists(username)"}
    else:
        if item is None or item.get("role") != args.role:
            parser.error("Account missing or role differs; no changes made")
        condition = {
            "ConditionExpression": "password_hash = :old AND #role = :role",
            "ExpressionAttributeNames": {"#role": "role"},
            "ExpressionAttributeValues": {":old": item["password_hash"], ":role": args.role},
        }
    password = getpass("New password (at least 12 characters): ")
    if not 12 <= len(password) <= 256:
        parser.error("Use 12–256 characters; no changes made")
    if password != getpass("Confirm password: "):
        parser.error("Passwords differ; no changes made")
    item["password_hash"] = hash_password(password)
    users_table.put_item(Item=item, **condition)
    saved = users_table.get_item(Key=key, ConsistentRead=True)["Item"]
    if not verify_password(password, saved["password_hash"]):
        raise RuntimeError("Saved password verification failed")
    print(f"Verified account: {args.username} ({saved['role']})")


if __name__ == "__main__":
    main()
