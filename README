# WalletMiner

This is a random multithread wallet miner for Bitcoin.

It generates a random 32 bytes bitcoin address and uses ECDSA followed by SHA256 and ripemd160 to generate the public address.
The address is then checked against a balance file containing all non-null bitcoin addresses and writes the private key followed by the balance if there is a match.

Note that there is 2^256 or 16^64 possibilities which is equal to ~1 x 10^77  
This is very unlikely to work.

# How to run it

Download the database dump containing the balances of all the used addresses.
This can be found here: https://gz.blockchair.com/bitcoin/addresses/

The file needs to be sorted.
Run the python tool

`python latest_balances_sort.py blockchair_bitcoin_addresses_latest.tsv`

Finally run the program with the balance file as argument:

`WalletMiner.exe M:\blockchair_bitcoin_addresses_latest.tsv`
