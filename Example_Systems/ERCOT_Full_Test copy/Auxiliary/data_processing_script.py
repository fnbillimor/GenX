import os
import pandas as pd

# Set the directory where the Excel files are located
excel_files_directory = 'Load_data_XL'  # Change this to your directory path
output_directory = 'Load_data'  # Change this to your desired output path

# Set the columns you want to sum. These should be present in all Excel sheets.
columns_to_sum = ['FAR_WEST', 'NORTH', 'WEST']  # Replace with your actual columns

# Create the output directory if it does not exist
os.makedirs(output_directory, exist_ok=True)

# Get a list of all Excel files in the directory
excel_files = [f for f in os.listdir(excel_files_directory) if f.endswith(('.xlsx', '.xls'))]

# Loop through the Excel files
for excel_file in excel_files:
    # Construct the full file path
    file_path = os.path.join(excel_files_directory, excel_file)
    
    # Read the Excel file into a Pandas DataFrame
    try:
        df = pd.read_excel(file_path, sheet_name=None)  # Read all sheets
    except Exception as e:
        print(f"Error reading {excel_file}: {e}")
        continue
    
    # Sum the columns for each sheet and add them to a new DataFrame
    result_df = pd.DataFrame()
    for sheet_name, sheet_df in df.items():
        # Ensure the columns exist in the sheet
        if not all(col in sheet_df for col in columns_to_sum):
            print(f"Skipping sheet '{sheet_name}' in file '{excel_file}' because it doesn't have the required columns.")
            continue
        
        # Calculate the sum and append to the result DataFrame
        sum_data = {col: sheet_df[col].sum() for col in columns_to_sum}
        sum_data['Sheet'] = sheet_name
        result_df = result_df.append(sum_data, ignore_index=True)
    
    # Generate output CSV file path
    output_csv_path = os.path.join(output_directory, os.path.splitext(excel_file)[0] + '_sum.csv')
    
    # Write the results to a CSV file
    result_df.to_csv(output_csv_path, index=False)
    print(f"Sum of specified columns from '{excel_file}' written to '{output_csv_path}'")

print("Processing complete.")

# Folder containing the Excel files
folder_path = 'path_to_folder_containing_excel_files'

# List to store the results
results = []

# Iterate over each file in the folder
for file_name in os.listdir(folder_path):
    if file_name.endswith('.xlsx'):
        file_path = os.path.join(folder_path, file_name)
        
        # Read the Excel file
        xls = pd.ExcelFile(file_path)
        
        # Iterate over each sheet in the Excel file
        for sheet_name in xls.sheet_names:
            df = pd.read_excel(xls, sheet_name)
            
            # Specify the columns to sum
            columns_to_sum = ['Column1', 'Column2']  # Update with your desired column names
            
            # Sum the specified columns along the rows
            df['Total'] = df[columns_to_sum].sum(axis=1)
            
            # Store the results
            results.append(df)
            
# Concatenate all results into a single DataFrame
final_result = pd.concat(results)

# Output the final result to a CSV file
final_result.to_csv('output.csv', index=False)	
