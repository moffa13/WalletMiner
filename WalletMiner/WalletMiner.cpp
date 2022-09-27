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
#include <sstream>
#include <iomanip>
#include <filesystem>
#include "ripemd160.c"
#include "base58encode.cpp"

using namespace std::chrono;

static constexpr size_t writeEveryXKeys = 1'000'000;
static std::atomic<size_t> done;
static std::atomic<size_t> doneStats;

static unsigned char max[32] = { 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF,
		0xFE, 0xBA, 0xAE, 0xDC, 0xE6, 0xAF, 0x48, 0xA0, 0x3B, 0xBF, 0xD2, 0x5E, 0x8C, 0xD0, 0x36, 0x41, 0x40 };

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
// If trueGenerator = true, the key will be max 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364140
// Which is 4.32420386565660042066383539350 � 10 ^ 29 less keys
std::vector<unsigned char> generateRandomPrvKey(bool trueGenerator = false) {
	std::vector<unsigned char> prvKey;
	std::random_device dev;
	std::mt19937 rng(dev());
	std::uniform_int_distribution<std::mt19937::result_type> udist{ 0, std::numeric_limits<unsigned char>().max() };

	bool ok = false;
	for (size_t i = 0; i < 32; i++) {
		if (!trueGenerator || ok) {
			prvKey.push_back(udist(rng));
		}
		else {
			unsigned char c;
			bool gen = false;
			while (!gen) {
				c = udist(rng);
				if (c < max[i]) {
					gen = true;
					ok = true;
				}
				else if (c == max[i]) {
					gen = true;
				}
			}
			prvKey.push_back(c);
		}
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

// Return the size of a line (same for all lines)
std::streamsize getLineSize(std::istream& is) {
	is.seekg(0, std::ios::beg);
	std::string t;
	std::getline(is, t);
	return is.tellg();	
}

// Return the size of a file
std::streamsize getFileSize(std::istream& is) {
	is.seekg(0, std::ios::end);
	return is.tellg();
}

// Read a line and go back to the beggining
std::string readLine(std::istream& is, std::streamsize pos) {
	std::string str;
	is.seekg(pos, std::ios::beg);
	std::getline(is, str);
	is.seekg(pos, std::ios::beg);
	return str;
}

// Performs a binary search
// File must be sorted in order for this to work
std::optional<std::string> fileSearch(std::streamsize size, std::streamsize lineSize, std::istream& is, std::string const& pubkey) {
	std::streamsize start = 0;
	std::streamsize end = size - lineSize;
	while (start <= end) {
		std::streamsize pos = (start + end) / 2;
		pos = (pos / lineSize) * lineSize;
		std::string line = readLine(is, pos);
		auto tabPos = line.find('\t');
		std::string realKey = line.substr(0, tabPos);
		if (realKey == pubkey) {
			std::string newStr = line.substr(tabPos + 1);
			if (!newStr.empty() && *newStr.rbegin() == '\r') {
				newStr.erase(newStr.length() - 1, 1);
			}
			newStr.erase(0, std::min(newStr.find_first_not_of('0'), newStr.size() - 1));
			return newStr;
		}
		else if (realKey < pubkey) {
			start = pos + lineSize;
		}
		else {
			end = pos - lineSize;
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

void check(const char* path, std::streamsize size, std::streamsize lineSize) {
	std::ifstream f{ path, std::ifstream::binary };
	if (f.fail()) {
		throw std::runtime_error{ "Error opening file." };
	}
	secp256k1_context* ctx = secp256k1_context_create(SECP256K1_CONTEXT_SIGN);
	while (true) {
		auto prv = generateRandomPrvKey();
		auto pub = privateKeyToAddress(prv, ctx);
		auto res = fileSearch(size, lineSize, f, pub);
		done++;
		doneStats++;
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

void writeStats() {
	if(doneStats > writeEveryXKeys){
		std::string end = " tested keys";
		std::string filename = std::filesystem::current_path().string() + "/walletminer.stats.txt";
		{
			std::fstream statsFile{ filename, std::fstream::in | std::fstream::out | std::fstream::app };
		}
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

	std::ifstream f{ argv[1], std::ifstream::binary };
	if (f.fail()) {
		std::cout << "Error opening file." << std::endl;
		exit(1);
	}

	auto size = getFileSize(f);
	auto lineSize = getLineSize(f);

	f.close();


	unsigned int _maxThreads = std::thread::hardware_concurrency(); // Concurrent threads
	std::vector<std::thread> threads;
	for (unsigned int i = 0; i < _maxThreads; i++) {
		threads.emplace_back(
			std::thread{ [argv, size, lineSize]() {
				try {
					check(argv[1], size, lineSize);
				}
				catch (std::exception e) {
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
