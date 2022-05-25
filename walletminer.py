import random
import ecdsa
import hashlib
import os
import base58
import requests
import time
from numba import jit

def privateKeyToAddress(Private_key):
	print(''.join('{:02x}'.format(x) for x in Private_key))
	# Private key to public key (ecdsa transformation)
	signing_key = ecdsa.SigningKey.from_string(Private_key, curve = ecdsa.SECP256k1)
	verifying_key = signing_key.get_verifying_key()
	print(''.join('{:02x}'.format(x) for x in verifying_key.to_string()))
	public_key = bytes.fromhex("04") + verifying_key.to_string()

	# hash sha 256 of pubkey
	sha256_1 = hashlib.sha256(public_key)

	# hash ripemd of sha of pubkey
	ripemd160 = hashlib.new("ripemd160")
	ripemd160.update(sha256_1.digest())

	# checksum
	hashed_public_key = bytes.fromhex("00") + ripemd160.digest()
	checksum_full = hashlib.sha256(hashlib.sha256(hashed_public_key).digest()).digest()
	checksum = checksum_full[:4]
	bin_addr = hashed_public_key + checksum

	# encode address to base58 and print
	result_address = base58.b58encode(bin_addr)
	return result_address.decode("utf-8") 

# Seeks back in the file until we reach a LR
# Set read to True to read the line once positionned
def findNextValidData(file, read=False):
	curr = file.tell()
	i = 0
	while True:
		i+=1
		seekVal = curr-i
		file.seek(seekVal, os.SEEK_SET)
		if seekVal == 0:
			break
		a = file.read(1)
		if a.decode('utf-8') == "\n":
			break
			
	if read:
		return file.readline()
	return 

def fileSearch(file, pubkey):
	file.seek(0, os.SEEK_END)
	findNextValidData(file)
	start = 0
	end = file.tell()
	file.seek(0, os.SEEK_SET)
	while start <= end:
		pos = int((start + end) / 2)
		file.seek(pos, os.SEEK_SET)
		key = findNextValidData(file, True).decode("utf-8")
		vals = key.split("\t")
		pubKeyFile = vals[0]

		pos = file.tell()
		if pubKeyFile == pubkey:
			return vals[1].rstrip('\r\n')
		elif pubKeyFile < pubkey:
			start = pos
		else:
			file.seek(pos - len(key) - 1, os.SEEK_SET)
			findNextValidData(file, False)
			end = file.tell()
	return False

def genRandomKey():
	return random.randbytes(32)

if __name__ == "__main__":

	now = time.time()
	count = 0
	countThreshold = 50

	with open('m:/blockchair_bitcoin_addresses_latest_sorted.tsv', "rb") as addressesFile:
		while(True):

			# Generate random privateKey
			private = genRandomKey()
			print("{}".format(private.hex()))
			# Extract public key from it
			pub = privateKeyToAddress(private)

			value = fileSearch(addressesFile, pub)

			count +=1

			if count >= countThreshold:
				timeDiff = time.time() - now
				r = count / timeDiff
				count = 0
				now = time.time()
				print('\r{} keys/s'.format(r))

			# A balance is available for that address
			if value is not False:
				with open('c:/Users/moffa/Desktop/balance.{}.txt'.format(os.getpid()), "a", encoding="utf8") as balanceFile:
					print("------------- NOT NULL BALANCE FOUND --------------------")
					balanceFile.write("{} => [{}], BALANCE: {}sat\n".format(private.hex(), pub, value))


# while(True):

# 	private = genRandomKey()
# 	pub = privateKeyToAddress(private)
# 	print('{} => [{}]'.format(private.hex(), pub))

# 	url = "https://api.blockcypher.com/v1/btc/main/addrs/{}/balance".format(pub)
# 	while True:
# 		try:
# 			r = requests.get(url)
# 			json['final_balance']
# 			break
# 		except Exception as e:
# 			print("Fetch error")
# 			time.sleep(1)
	
# 	json = r.json()
# 	#json['final_balance'], json['total_received'], json['total_sent']
# 	if float(json['final_balance']) > 0.0:
# 		with open('c:/Users/moffa/Desktop/balance.txt', "a", encoding="utf8") as balanceFile:
# 			print("------------- NOT NULL BALANCE FOUND --------------------")
# 			balanceFile.write("{} => [{}], BALANCE: {} BTC\n".format(private.hex(), pub, json['final_balance']))
	