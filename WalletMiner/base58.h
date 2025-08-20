inline static constexpr const uint8_t base58map[] = {
	'1', '2', '3', '4', '5', '6', '7', '8',
	'9', 'A', 'B', 'C', 'D', 'E', 'F', 'G',
	'H', 'J', 'K', 'L', 'M', 'N', 'P', 'Q',
	'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y',
	'Z', 'a', 'b', 'c', 'd', 'e', 'f', 'g',
	'h', 'i', 'j', 'k', 'm', 'n', 'o', 'p',
	'q', 'r', 's', 't', 'u', 'v', 'w', 'x',
	'y', 'z' };

std::string base58Encode(const std::array<uint8_t, 25>& data, const uint8_t* mapping)
{
	std::vector<uint8_t> digits((data.size() * 138 / 100) + 1);
	size_t digitslen = 1;
	for (size_t i = 0; i < data.size(); i++)
	{
		uint32_t carry = static_cast<uint32_t>(data[i]);
		for (size_t j = 0; j < digitslen; j++)
		{
			carry = carry + static_cast<uint32_t>(digits[j] << 8);
			digits[j] = static_cast<uint8_t>(carry % 58);
			carry /= 58;
		}
		for (; carry; carry /= 58)
			digits[digitslen++] = static_cast<uint8_t>(carry % 58);
	}
	std::string result;
	for (size_t i = 0; i < (data.size() - 1) && !data[i]; i++)
		result.push_back(mapping[0]);
	for (size_t i = 0; i < digitslen; i++)
		result.push_back(mapping[digits[digitslen - 1 - i]]);
	return result;
}



std::array<uint8_t, 25> base58Decode(const std::string& str) {
	// mapping base58 → valeur numérique
	int map[256];
	std::fill(std::begin(map), std::end(map), -1);
	for (int i = 0; i < 58; i++) {
		map[base58map[i]] = i;
	}

	std::vector<uint8_t> out(25); // 25 octets résultat
	int zeros = 0;

	// Compter les '1' en tête (== 0x00 en binaire)
	while (zeros < (int)str.size() && str[zeros] == '1') {
		zeros++;
	}

	std::vector<uint8_t> b256((str.size() - zeros) * 733 / 1000 + 1);

	for (size_t i = zeros; i < str.size(); i++) {
		int carry = map[(unsigned char)str[i]];
		if (carry == -1) throw std::runtime_error("Invalid base58 char");

		int j = 0;
		for (auto it = b256.rbegin(); (carry != 0 || j < (int)b256.size()) && it != b256.rend(); ++it, ++j) {
			carry += 58 * (*it);
			*it = carry % 256;
			carry /= 256;
		}
	}

	// Skip leading zeroes
	auto it = std::find_if(b256.begin(), b256.end(), [](uint8_t c) { return c != 0; });
	std::vector<uint8_t> decoded(zeros + (b256.end() - it), 0);
	std::copy(it, b256.end(), decoded.begin() + zeros);

	if (decoded.size() != 25)
		throw std::runtime_error("Decoded base58 length != 25");

	std::array<uint8_t, 25> arr{};
	std::copy(decoded.begin(), decoded.end(), arr.begin());
	return arr;
}


