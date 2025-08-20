#include <iostream>
#include <optional>
#include <string>
#include <fstream>
#include <vector>
#include <atomic>
#include <random>
#include <algorithm>
#include <thread>
#include <secp256k1.h>
#include <openssl/sha.h>
#include <cassert>
#include <chrono>
#include <array>
#include <sstream>
#include <iomanip>
#include <memory>
#include <filesystem>
#include <unordered_map>
#include "ripemd160.c"
#include "base58.h"

#pragma warning(disable : 4996) //_CRT_SECURE_NO_WARNINGS

using namespace std::chrono;

static constexpr size_t writeEveryXKeys = 1'000'000;
static std::atomic<size_t> done;
static std::atomic<size_t> doneStats;

// Struct to be able to make a hash out of pub addr
struct AddressHash {
	std::size_t operator()(std::array<uint8_t, 36> const& a) const noexcept {
		std::size_t h = 1469598103934665603ull;
		for (uint8_t c : a) {
			if (c == '\0') break;
			h ^= c;
			h *= 1099511628211ull;
		}
		return h;
	}
};

// Struct that accepts the comparison between 2 addr
struct AddressEq {
	bool operator()(std::array<uint8_t, 36> const& a, std::array<uint8_t, 36> const& b) const noexcept {
		return std::strcmp(reinterpret_cast<const char*>(a.data()), reinterpret_cast<const char*>(b.data())) == 0;
	}
};

// The hash map containing all the pub addresses in base58
static std::unordered_map<std::array<uint8_t, 36>, uint64_t, AddressHash, AddressEq> addresses;


const std::array<uint8_t, 32> SECP256K1_N = {
	0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,
	0xFF,0xFF,0xFF,0xFF,0xFE,0xBA,0xAE,0xDC,
	0xE6,0xAF,0x48,0xA0,0x3B,0xBF,0xD2,0x5E,
	0x8C,0xD0,0x36,0x41,0x40,0x00,0x00,0x00
};


// Loads all addresses with their balance into a map
// Format is P2PKH
// Will only load keys starting with 1 or 3
void loadValidAddresses(const char* path){
	std::cout << "Loading keys..." << std::endl;
	std::ifstream f{ path };
	if (f.fail()) {
		throw std::runtime_error{ "Error opening addresses file." };
	}
	std::string line;
	while(std::getline(f, line)){
		if (line.empty()) continue;
		auto pos = line.find_first_of('\t');
		if (pos == std::string::npos) continue;

		std::string address = line.substr(0, pos);
		uint64_t balance;
		try {
			balance = std::stoull(line.substr(pos + 1));
		}
		catch (...) {
			continue;
		}

		if (!(address.starts_with("1") || address.starts_with("3"))) {
			continue;
		}

		try {
			std::array<uint8_t, 36> key{0};
			std::strncpy(reinterpret_cast<char*>(key.data()), address.c_str(), 35);
			key.back() = '\0';
			addresses.emplace(key, balance);
		}
		catch (...) {
			// We got an invalid base58 addr in the file
			continue;
		}
	}
	std::cout << "Loaded " << addresses.size() << " addresses from file" << std::endl;
}


// check if addr is in addresses
inline std::optional<uint64_t> checkAddr(const std::string& addr){

	std::array<uint8_t, 36> key{0};
	std::strncpy(reinterpret_cast<char*>(key.data()), addr.c_str(), 35);
	key.back() = '\0';

	auto it = addresses.find(key);
	if(it != addresses.end()){
		return it->second;
	}
	return std::nullopt;
}

// Applies sha256 on a raw array and returns an std::array of size 32
inline std::array<uint8_t, 32> sha256(const uint8_t* data, size_t len) {
	std::array<uint8_t, 32> sha256r;
	SHA256(data, len, sha256r.data());
	return sha256r;
}

// Return a public key in the compressed form
// Key is base58 encoded
std::string privateKeyToAddress(std::array<uint8_t, 32> const& prvkey, secp256k1_context* ctx) {
	secp256k1_pubkey pubkey;

	if (secp256k1_ec_pubkey_create(ctx, &pubkey, prvkey.data()) == 0) {
		throw std::runtime_error{ "Cannot make pubkey" };
	}
	
	// Serialize pub key in compressed form
	uint8_t serializedpubKey[33];
	size_t ss = 33;
	secp256k1_ec_pubkey_serialize(ctx, serializedpubKey, &ss, &pubkey, SECP256K1_EC_COMPRESSED);

	// 0x00 + ripemd160 of sha256res
	auto sha = sha256(serializedpubKey, ss);
	uint8_t ripemd160r[21] = { 0 };
	ripemd160(sha.data(), sha.size(), ripemd160r + 1);

	// Copy ripemd160 in final container
	std::array<uint8_t, 25> hashPubKey{};
	std::copy_n(ripemd160r, 21, hashPubKey.begin());

	// 2 times checksum
	auto checksum = sha256(hashPubKey.data(), 21);
	checksum = sha256(checksum.data(), checksum.size());

	// Add 4 first bytes to final container
	std::copy_n(checksum.begin(), 4, hashPubKey.begin() + 21);

	// Return the base58 encoded form
	return base58Encode(hashPubKey, base58map);
}


// 64 chars hex string to 32 bytes private key
std::vector<uint8_t > stringToPrvKey(std::string const& str) {
	static const std::string values{ "0123456789abcdef" };
	std::vector<uint8_t > realHash;
	realHash.reserve(32);
	int i = 0;
	for (std::string::const_iterator it{ str.begin() }; it != str.end();)
	{
		size_t f1 = values.find(*it++) * 16;
		size_t f2 = values.find(*it++);
		realHash.push_back(static_cast<uint8_t >(f1 + f2));
		i++;
	}
	return realHash;
}

// 32 bytes private key to readable 64 chars hex string
std::string prvKeyToString(std::array<uint8_t, 32> const& prvKey) {
	std::stringstream ss;
	ss << std::hex;

	for (uint8_t  i : prvKey) {
		ss << std::setw(2) << std::setfill('0') << static_cast<int>(i);
	}

	return ss.str();	
}

// returns true if the generated private key is in the accepted range for a bitcoin address
bool checkValidPrvKey(const std::array<uint8_t, 32>&v) {
	return std::lexicographical_compare(
		v.begin(), v.end(),
		SECP256K1_N.begin(), SECP256K1_N.end()
	);
}

// Generates a random 32 bytes private key
// If trueGenerator = true, the key will be max 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364140
// Which is 4.32420386565660042066383539350 X 10 ^ 29 less keys than the total permitted in 32 bytes
std::array<uint8_t, 32> generateRandomPrvKey(bool trueGenerator = false) {
	thread_local std::mt19937 rng(std::random_device{}());
	std::uniform_int_distribution<uint64_t> udist{ 0, std::numeric_limits<uint64_t>().max() };

	std::array<uint8_t, 32> key{};
	do {
		for (int i = 0; i < 4; i++) {
			uint64_t part = udist(rng);
			for (int j = 0; j < 8; j++) {
				key[i * 8 + j] = static_cast<uint8_t >(part & 0xFF);
				part >>= 8;
			}
		}
	} while (trueGenerator && !checkValidPrvKey(key));
	
	return key;

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
	secp256k1_context* ctx = secp256k1_context_create(SECP256K1_CONTEXT_SIGN);
	while (true) {
		auto prv = generateRandomPrvKey(true);
		auto pub = privateKeyToAddress(prv, ctx);
		auto res = checkAddr(pub);
		done++;
		doneStats++;
		if (res) {
			// Really unlikely to happen, no need to sync =D
			std::cout << "-------------------- NON NULL BALANCE FOUND --------------------" << std::endl;
			std::ofstream os{ std::filesystem::current_path().string() + "/walletminer.balance." + std::to_string(std::hash<std::thread::id>{}(std::this_thread::get_id())) + ".txt", std::ofstream::app};
			std::string addrBal{ prvKeyToString(prv) + " => [" + pub + "]" + ", BALANCE: " + std::to_string(*res) + "sat\n"};
			os.write(addrBal.c_str(), addrBal.size());
			os.close();
		}
	}
	secp256k1_context_destroy(ctx);
}

void writeStats() {
	if(doneStats > writeEveryXKeys){
		std::string end = " tested keys";
		std::string filename = std::filesystem::current_path().string() + "/walletminer.stats.txt";
		std::fstream statsFile{ filename, std::fstream::in | std::fstream::out};
		if (statsFile.fail()) {
			return;
		}

		std::string line;
		std::getline(statsFile, line);
		statsFile.clear(); // Clear failbit

		const char* digits = "0123456789";
		std::size_t firstPos = line.find_first_of(digits);
		if (firstPos != std::string::npos) {
			std::size_t lastPos = line.find_first_not_of(digits);
			doneStats += std::atoi(line.substr(firstPos, lastPos - firstPos).c_str());
		}

		statsFile.seekg(0, std::ios::beg);
		statsFile << (std::to_string(doneStats) + end);

		statsFile.close();
		doneStats = 0;
	}
}

int main(int argc, char** argv) {

	if (argc < 2) {
		std::cout << "Usage WalletMiner.exe <balance_file>" << std::endl;
		return 1;
	}


	// Check that the built address is right for the private key
	secp256k1_context* ctx = secp256k1_context_create(SECP256K1_CONTEXT_SIGN);

	assert(
		privateKeyToAddress(
			stringToPrvKey("be63955589062b68320f0a3d5b450551c67bbb5f6e5b34cec57738f3a96316a9"), ctx)
			== "1Dai8FBumerEYMzijW7hfMgD45HowqYzVP"
	);

	secp256k1_context_destroy(ctx);

	try {
		loadValidAddresses(argv[1]);
	}
	catch (const std::exception& e) {
		std::cout << "Error loading file" << std::endl;
		std::cout << e.what() << std::endl;
		return 2;
	}

	// Using a random pub key in the file to see if it finds it in addresses
	assert(checkAddr("1LruNZjwamWJXThX2Y8C2d47QqhAkkc5os"));
	

	unsigned int _maxThreads = std::thread::hardware_concurrency(); // Concurrent threads
	std::vector<std::thread> threads;
	for (unsigned int i = 0; i < _maxThreads; i++) {
		threads.emplace_back(
			std::thread{ [argv]() {
				try {
					check(argv[1]);
				}
				catch (const std::exception& e) {
					std::cout << e.what() << std::endl;
					exit(1);
				}
			}} 
		);
	}


	time_point<system_clock, milliseconds> lastUpdate = time_point_cast<milliseconds>(system_clock::now());
	while (true) {
		std::this_thread::sleep_for(std::chrono::milliseconds(200));
		auto elapsedTime = getElapsedTime(lastUpdate);
		lastUpdate = time_point_cast<milliseconds>(system_clock::now());
		auto speed = getSpeed(elapsedTime, done.load());
		writeStats();
		done = 0;
		std::cout << "\r" << speed << " keys/s             " << std::flush;
	}

	return 0;
}
