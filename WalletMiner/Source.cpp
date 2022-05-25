#include <iostream>
#include <optional>
#include <string>
#include <fstream>
#include <vector>
#include <random>
#include <algorithm>
#include <thread>
#include <secp256k1.h>
#include <openssl/sha.h>
#include <cassert>
#include <chrono>
#include <sstream>
#include <iomanip>
#include <filesystem>
#include "ripemd160.c"
#include "base58encode.cpp"


using namespace std::chrono;

static std::atomic<size_t> done;

// Applies sha256 on a vector and writes it to that same vector
void sha256(std::vector<unsigned char>& vector) {
	unsigned char sha256r[SHA256_DIGEST_LENGTH];
	SHA256(vector.data(), vector.size(), std::begin(sha256r));
	vector.clear();
	std::copy(std::begin(sha256r), std::end(sha256r), std::back_inserter(vector));
}

// Extract the public key address from the 32 bytes private key
// In base58 format
std::string privateKeyToAddress(std::vector<unsigned char> const& prvkey, secp256k1_context* ctx) {
	
	secp256k1_pubkey pubkey;

	// Make public key
	if (secp256k1_ec_pubkey_create(ctx, &pubkey, prvkey.data()) == 0) {
		throw std::runtime_error{ "Cannot make pubkey" };
	}

	// Serialize public key in 65 byte array
	unsigned char serializedpubKey[65];
	size_t ss = 65;
	secp256k1_ec_pubkey_serialize(ctx, serializedpubKey, &ss, &pubkey, SECP256K1_EC_UNCOMPRESSED);


	// sha256 of serializedpubKey
	unsigned char sha256res[SHA256_DIGEST_LENGTH];
	SHA256(serializedpubKey, 65, std::begin(sha256res));

	// 0x00 + ripemd160 of sha256res
	unsigned char ripemd160r[21] = {0};
	ripemd160(std::begin(sha256res), SHA256_DIGEST_LENGTH, std::begin(ripemd160r) + 1);

	// copy of ripemd160r
	std::vector<unsigned char> hashPubKey{ std::begin(ripemd160r), std::end(ripemd160r) };

	// Checksum is double sha256 of hashPubKey
	std::vector<unsigned char> checksumFull{ hashPubKey };
	checksumFull.reserve(32);
	sha256(checksumFull);
	sha256(checksumFull);

	// hashPubKey + checksum
	std::copy(checksumFull.begin(), checksumFull.begin() + 4, std::back_inserter(hashPubKey));

	return EncodeBase58(hashPubKey, base58map);
}

// 64 chars hex string to 32 bytes private key
std::vector<unsigned char> stringToPrvKey(std::string const& str) {
	static const std::string values{ "0123456789abcdef" };
	std::vector<unsigned char> realHash;
	realHash.reserve(32);
	int i = 0;
	for (std::string::const_iterator it{ str.begin() }; it != str.end();)
	{
		size_t f1 = values.find(*it++) * 16;
		size_t f2 = values.find(*it++);
		realHash.push_back(static_cast<unsigned char>(f1 + f2));
		i++;
	}
	return realHash;
}

// 32 bytes private key to readable 64 chars hex string
std::string prvKeyToString(std::vector<unsigned char> const& prvKey) {
	std::stringstream ss;
	ss << std::hex;

	for (unsigned char i : prvKey) {
		ss << std::setw(2) << std::setfill('0') << static_cast<int>(i);
	}

	return ss.str();	
}

// Generates a random 32 bytes private key
std::vector<unsigned char> generateRandomPrvKey() {
	std::vector<unsigned char> prvKey;
	std::random_device dev;
	std::mt19937 rng(dev());
	std::uniform_int_distribution<std::mt19937::result_type> udist{ 0, std::numeric_limits<unsigned char>().max() };
	for (size_t i = 0; i < 32; i++) {
		prvKey.push_back(udist(rng));
	}
	return prvKey;
}

// Treating the private key as an int and increment by 1
void incrementPrvKey(std::vector<unsigned char>& prvKey) {
	for (int8_t i = 31; i >= 0; i--) {
		if (prvKey[i] == std::numeric_limits<unsigned char>().max()) {
			prvKey[i] = 0;
		}
		else {
			prvKey[i]++;
			break;
		}
	}
}

// Goes back until it gets to start of line
// Reads it and returns if read = true
std::optional<std::string> findNextValidData(std::istream& is, bool read = false) {
	std::streamsize curr = is.tellg();
	std::streamsize i = 0;
	while (true) {
		i++;
		std::streamsize seekVal = curr - i;
		if (seekVal <= 0) break;
		is.seekg(seekVal, std::ios::beg);
		char letter;
		is.get(letter);
		if (letter == '\n') {
			break;
		}
	}
	if (read) {
		std::string line;
		std::getline(is, line);
		return line;
	}
	return std::nullopt;
}

// Performs a binary search
// File must be sorted in order for this to work
std::optional<std::string> fileSearch(std::istream& is, std::string const& pubkey) {
	is.seekg(0, std::ios::end);
	findNextValidData(is, false);
	std::streamsize start = 0;
	std::streamsize end = is.tellg();
	is.seekg(0, std::ios::beg);
	while (start <= end) {
		std::streamsize pos = (start + end) / 2;
		is.seekg(pos, std::ios::beg);
		auto opt = findNextValidData(is, true);
		std::streamsize newPos = is.tellg();
		std::string& key = *opt;
		auto tabPos = key.find('\t');
		std::string realKey = key.substr(0, tabPos);
		if (realKey == pubkey) {
			std::string newStr = key.substr(tabPos + 1);
			if (!newStr.empty() && *newStr.rbegin() == '\r') {
				newStr.erase(newStr.length() - 1, 1);
			}
			return newStr;
		}
		else if (realKey < pubkey) {
			start = newPos;
		}
		else {
			is.seekg(newPos - key.size() - 1 - 1, std::ios::beg);
			findNextValidData(is, false);
			end = is.tellg();
		}
	}
	return std::nullopt;
}

auto getElapsedTime(time_point<system_clock, milliseconds> lastUpdate) {
	time_point<system_clock, milliseconds> now = time_point_cast<milliseconds>(system_clock::now());
	auto delay = duration_cast<milliseconds>(now - lastUpdate);
	auto delay_ms = delay.count();
	return delay_ms;
}

template<typename T, typename U>
double getSpeed(T elapsedTime, U processedNumber) {
	double ratio = elapsedTime / 1000.0;
	if (ratio == 0) return 0.0;
	return processedNumber / ratio;
}

void check(const char* path) {
	std::ifstream f{ path, std::ifstream::binary };
	if (f.fail()) {
		throw std::runtime_error{ "Error opening file." };
	}
	secp256k1_context* ctx = secp256k1_context_create(SECP256K1_CONTEXT_SIGN);
	while (true) {
		auto prv = generateRandomPrvKey();
		auto pub = privateKeyToAddress(prv, ctx);
		auto res = fileSearch(f, pub);
		done++;
		if (res) {
			// Really unlikely to happen, no need to sync =D
			std::cout << "-------------------- NON NULL BALANCE FOUND --------------------" << std::endl;
			std::ofstream os{ std::filesystem::current_path().string() + "/walletminer.balance." + std::to_string(std::hash<std::thread::id>{}(std::this_thread::get_id())) + ".txt", std::ofstream::app};
			std::string addrBal{ prvKeyToString(prv) + " => [" + pub + "]" + ", BALANCE: " + *res + "sat\n" };
			os.write(addrBal.c_str(), addrBal.size());
			os.close();
		}
	}
	secp256k1_context_destroy(ctx);
	f.close();
}


int main(int argc, char** argv) {

	if (argc < 2) {
		std::cout << "Usage WalletMiner.exe <balance_file>" << std::endl;
		std::cout << "File must be sorted in order for the binary search to work." << std::endl;
		return 1;
	}

	// Check that the built address is right for the private key
	secp256k1_context* ctx = secp256k1_context_create(SECP256K1_CONTEXT_SIGN);
	assert(
		privateKeyToAddress(
			stringToPrvKey("be63955589062b68320f0a3d5b450551c67bbb5f6e5b34cec57738f3a96316a9"), ctx)
			== "18pRzZBpMyrfPbcBBQcfVYMXoibm6fhqYs"
	);
	secp256k1_context_destroy(ctx);

	unsigned int _maxThreads = std::thread::hardware_concurrency(); // Concurrent threads
	std::vector<std::thread> threads;
	for (unsigned int i = 0; i < _maxThreads; i++) {
		threads.emplace_back(std::thread{ [argv]() {check(argv[1]); } });
	}

	time_point<system_clock, milliseconds> lastUpdate = time_point_cast<milliseconds>(system_clock::now());
	while (true) {
		std::this_thread::sleep_for(std::chrono::milliseconds(200));
		auto elapsedTime = getElapsedTime(lastUpdate);
		lastUpdate = time_point_cast<milliseconds>(system_clock::now());
		auto speed = getSpeed(elapsedTime, done.load());
		done = 0;
		std::cout << "\r" << speed << " keys/s             " << std::flush;
	}

	return 0;
}