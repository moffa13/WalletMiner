import sys
import os

def build_index(filename, sort_col):
    print("Generating index...")
    index = []
    f = open(filename)
    while True:
        offset = f.tell()
        line = f.readline()
        if not line:
            break
        length = len(line)
        col = line.split('\t')[sort_col].strip()
        index.append((col, offset, length))
    f.close()
    index.sort()
    return index

def print_sorted(filename, newFilename, col_sort):
    index = build_index(filename, col_sort)
    f = open(filename)
    f2 = open(newFilename, 'w')
    print("Writing file...")
    for col, offset, length in index:
        f.seek(offset)
        f2.write(f.read(length).rstrip('\n')+"\n")

if __name__ == '__main__':
    if len(sys.argv) < 2:
        print("usage: python latest_balances_sort.py <balance_file>")
        exit(1)
    filename = sys.argv[1]
    sorted_filename = os.getcwd() + "/blockchair_bitcoin_addresses_latest_sorted.tsv"
    print("Generating sorted file...")
    print_sorted(filename, sorted_filename, 0)
    print("Done, file written to {}".format(sorted_filename))