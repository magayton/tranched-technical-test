from Crypto.Hash import keccak

# From storage slots
hidden_password = 544387104597
salt = 1754933492

value = hidden_password + salt
encoded = value.to_bytes(32, byteorder='big')

k = keccak.new(digest_bits=256)
k.update(encoded)
password = int.from_bytes(k.digest(), byteorder='big')

print("Password:", password)
