import sys
import os

def build_index(filename, sort_col, onlyLegacy = True):
    print("Generating index...")
    max_length = 0
    index = []
    f = open(filename)
    while True:
        offset = f.tell()
        line = f.readline()
        if not line:
            break
        if onlyLegacy and line[0] != '1':
            continue
        length = len(line) - 1 # remove \n from the size
        max_length = length if length > max_length else max_length
        col = line.split('\t')[sort_col].strip()
        index.append((col, offset, length))
    f.close()
    print("Sorting index...")
    index.sort()
    return (max_length, index)

def print_sorted(filename, newFilename, col_sort):
    max_length, index = build_index(filename, col_sort)
    f = open(filename)
    f2 = open(newFilename, 'w')
    print("Writing file...")
    for _, offset, length in index:
        f.seek(offset)
        text = f.read(length).rstrip('\n')
        sep = text.split("\t")
        if not sep[1].isnumeric() : continue
        text = sep[0] + "\t{:0{prec}d}".format(int(sep[1]), prec=len(sep[1]) + max_length - len(text))
        f2.write(text + "\n")

if __name__ == '__main__':
    if len(sys.argv) < 2:
        print("usage: python latest_balances_sort.py <balance_file>")
        exit(1)
    filename = sys.argv[1]
    sorted_filename = os.getcwd() + "/blockchair_bitcoin_addresses_latest_sorted.tsv"
    print("Generating sorted file...")
    print_sorted(filename, sorted_filename, 0)
    print("Done, file written to {}".format(sorted_filename))