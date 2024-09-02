#!/bin/bash

DOMAIN=$1
OUTPUT_DIR="$DOMAIN-enum"
LIVE_SUBS="$OUTPUT_DIR/live_subs.txt"
FINAL_OUTPUT="$OUTPUT_DIR/final_report.txt"
KATANA_OUTPUT_DIR="$OUTPUT_DIR/katana_crawls"
WAYBACK_OUTPUT="$OUTPUT_DIR/wayback_urls.txt"
FILTERED_URLS="$OUTPUT_DIR/filtered_urls.txt"

# Ensure the script stops on error
set -e

mkdir -p $OUTPUT_DIR $JS_OUTPUT_DIR $KATANA_OUTPUT_DIR

# Initialize the final report file
echo "[+] Starting enumeration for $DOMAIN" > $FINAL_OUTPUT
echo "========================================" >> $FINAL_OUTPUT

# 1. Subdomain Enumeration
echo "[+] Enumerating subdomains..."

(
    subfinder -d $DOMAIN -o $OUTPUT_DIR/subfinder_subs.txt -silent
    assetfinder --subs-only $DOMAIN | tee $OUTPUT_DIR/assetfinder_subs.txt
    findomain -t $DOMAIN -u $OUTPUT_DIR/findomain_subs.txt -q
    sublist3r -d $DOMAIN -t 3 -o $OUTPUT_DIR/sublist3r.txt
) &

wait

# Combine results, remove duplicates, and sort alphabetically
cat $OUTPUT_DIR/subfinder_subs.txt $OUTPUT_DIR/assetfinder_subs.txt $OUTPUT_DIR/findomain_subs.txt $OUTPUT_DIR/sublist3r.txt | sort -u > $OUTPUT_DIR/all_subs.txt

echo "[Subdomains Found]" >> $FINAL_OUTPUT
echo "Total: $(wc -l < $OUTPUT_DIR/all_subs.txt)" >> $FINAL_OUTPUT
cat $OUTPUT_DIR/all_subs.txt >> $FINAL_OUTPUT
echo "----------------------------------------" >> $FINAL_OUTPUT

# 2. DNS Resolution Check with DNSX
echo "[+] Resolving DNS for subdomains..."
dnsx -l $OUTPUT_DIR/all_subs.txt -o $LIVE_SUBS -silent

# Sort the live subdomains file alphabetically
sort -u $LIVE_SUBS -o $LIVE_SUBS

echo "[Resolved Subdomains]" >> $FINAL_OUTPUT
echo "Total: $(wc -l < $LIVE_SUBS)" >> $FINAL_OUTPUT
cat $LIVE_SUBS >> $FINAL_OUTPUT
echo "----------------------------------------" >> $FINAL_OUTPUT

# 3. Wayback URL Extraction
echo "[+] Extracting URLs from Wayback Machine..."
{
    echo "[Wayback URLs]"
    for subdomain in $(cat $LIVE_SUBS); do
        echo "Wayback URLs for $subdomain:"
        gau --subs $subdomain
        echo "----------------------------------------"
    done
} > $WAYBACK_OUTPUT &

wait

# Sort the Wayback output alphabetically and remove duplicates
sort -u $WAYBACK_OUTPUT -o $WAYBACK_OUTPUT

# 4. Katana Web Crawling
echo "[+] Crawling subdomains with Katana..."
{
    for subdomain in $(cat $LIVE_SUBS); do
        KATANA_OUTPUT_FILE="$KATANA_OUTPUT_DIR/$subdomain.txt"
        echo "Katana crawl for $subdomain:" > $KATANA_OUTPUT_FILE
        katana -u $subdomain -d 5 -silent -jc >> $KATANA_OUTPUT_FILE
        echo "----------------------------------------" >> $KATANA_OUTPUT_FILE
        
        # Sort each Katana output file alphabetically and remove duplicates
        sort -u $KATANA_OUTPUT_FILE -o $KATANA_OUTPUT_FILE
    done
} &

wait

# 5. Filter Live URLs with HTTPX
echo "[+] Filtering live URLs..."
cat $WAYBACK_OUTPUT $KATANA_OUTPUT_DIR/*.txt | sort -u | httpx -status-code -follow-redirects -silent -mc 200,301,302,403,401,500,501 -o $FILTERED_URLS

# Sort the filtered URLs alphabetically and remove duplicates
sort -u $FILTERED_URLS -o $FILTERED_URLS

echo "[Filtered URLs]" >> $FINAL_OUTPUT
echo "Total: $(wc -l < $FILTERED_URLS)" >> $FINAL_OUTPUT
echo "----------------------------------------" >> $FINAL_OUTPUT

# Organize URLs by subdomain and status code
{
    for subdomain in $(cat $LIVE_SUBS); do
        echo "----------------------------------------"
        echo "Subdomain: $subdomain"
        echo "----------------------------------------"
        
        # Collect all URLs for the exact subdomain, normalize them, sort them, and remove duplicates
        grep -E "https?://$subdomain(\$|/|:)" $FILTERED_URLS | while read -r line; do
            url=$(echo $line | cut -d' ' -f1 | sed 's:/$::')  # Normalize by removing trailing slash
            status_code=$(echo $line | cut -d' ' -f2)
            echo "[$status_code] $url"
        done | sort -u  # Ensure unique entries

        echo "----------------------------------------"
    done
} >> $FINAL_OUTPUT

# Final output
echo "[+] Enumeration complete. See the results in $FINAL_OUTPUT"