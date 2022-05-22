def build_index(filename, sort_col):
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
    for col, offset, length in index:
        f.seek(offset)
        f2.write(f.read(length).rstrip('\n')+"\n")

if __name__ == '__main__':
    filename = 'c:/Users/moffa/Desktop/blockchair_bitcoin_addresses_latest.tsv'
    sorted_filename = 'm:/blockchair_bitcoin_addresses_latest_sorted.tsv'
    sort_col = 0
    print_sorted(filename, sorted_filename, sort_col)