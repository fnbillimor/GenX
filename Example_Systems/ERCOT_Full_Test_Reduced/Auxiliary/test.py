import os
import pandas as pd
'''
# Path to the folder containing the Excel files
folder_path = 'Load_data_XL'
output_directory = 'Load_data'  # Change this to your desired output path


# Iterate over each file in the folder
for file_name in os.listdir(folder_path):
    if file_name.endswith('.xls') or file_name.endswith('.xlsx'):
        # Read the Excel file
        file_path = os.path.join(folder_path, file_name)
        df = pd.read_excel(file_path)
        
        # Perform the operations
        df['TRE_WEST'] = df['FAR_WEST'] + df['NORTH'] + df['WEST']
        df['TRE'] = df['COAST'] + df['EAST'] + df['NORTH_C'] + df['SOUTHERN'] + df['SOUTH_C']

        # Select only the columns you want in the output
        result_df = df[['TRE_WEST','TRE']]
        
        # Write the results to a corresponding CSV file
        csv_file_name = os.path.splitext(file_name)[0] + '.csv'
        result_df.to_csv(os.path.join(output_directory, csv_file_name), index=False)

print("Results have been written to CSV files in the folder.")

# Specify the range of columns to select from the source CSV file
start_col = 1  # 0-indexed
end_col = 33  # 0-indexed

# Read data from the source CSV file
source_file = 'Generators_variability.csv'
source_df = pd.read_csv(source_file)

# Get the column names to copy
columns_to_copy = source_df.columns[start_col:end_col+1]

# Specify the folder containing the target CSV files
folder_path = 'Generators_variability/'

# Loop through all CSV files in the folder
for file_name in os.listdir(folder_path):
    if file_name.endswith('.csv'):
        target_file = os.path.join(folder_path, file_name)
        
        # Read data from the target CSV file
        target_df = pd.read_csv(target_file)
        
        # Insert selected columns from the source file to the target file
        for col in columns_to_copy:
            target_df.insert(0, col, source_df[col])
        
        # Write the updated data to the target CSV file
        target_df.to_csv(target_file, index=False)
        
        print(f'Columns inserted into {file_name}')

print('All files processed.')

# Path to the folder containing CSV files to compare
folder_path = 'Generators_variability/test_folder'

# Path to the particular CSV file to compare against
reference_file = 'Generators_variability/Generators_variability_scenario_1.csv'

# Read the reference CSV file
reference_df = pd.read_csv(reference_file)

# Iterate through each CSV file in the folder
for file_name in os.listdir(folder_path):
    if file_name.endswith('.csv'):
        file_path = os.path.join(folder_path, file_name)
        
        # Read the current CSV file
        current_df = pd.read_csv(file_path)

        # Add missing columns from the reference file
        missing_columns = set(reference_df.columns) - set(current_df.columns)
        for column in missing_columns:
            current_df[column] = reference_df[column]
        
        # Rearrange columns in the same sequence as the reference file
        current_df = current_df[reference_df.columns]
        
        # Save the updated CSV file
        current_df.to_csv(file_path, index=False)

print('All files processed.')
'''
# Path to the folder containing CSV files
folder_path = 'Generators_variability'

# List of column names to rename
columns_to_rename = {'TRE_WEST_wind_1':	'TRE_WEST_landbasedwind_class1_moderate_1', 'TRE_WEST_wind_2':	'TRE_WEST_landbasedwind_class1_moderate_2',	'TRE_WEST_wind_3': 'TRE_WEST_landbasedwind_class1_moderate_3', 'TRE_wind_4': 'TRE_landbasedwind_class1_moderate_4', 'TRE_wind_5': 'TRE_landbasedwind_class1_moderate_5', 'TRE_wind_6': 'TRE_landbasedwind_class1_moderate_6', 'TRE_WEST_solar_pv_7': 'TRE_WEST_utilitypv_class1_moderate_1', 'TRE_WEST_solar_pv_8':	'TRE_WEST_utilitypv_class1_moderate_2', 'TRE_WEST_solar_pv_9': 'TRE_WEST_utilitypv_class1_moderate_3', 'TRE_solar_pv_10': 'TRE_utilitypv_class1_moderate_4', 'TRE_solar_pv_11': 'TRE_utilitypv_class1_moderate_5'}

# Iterate through each CSV file in the folder
for file_name in os.listdir(folder_path):
    if file_name.endswith('.csv'):
        file_path = os.path.join(folder_path, file_name)
        
        # Read the CSV file
        df = pd.read_csv(file_path)
        
        # Rename specific columns
        df.rename(columns=columns_to_rename, inplace=True)
        
        # Save the updated CSV file
        df.to_csv(file_path, index=False)


# Path to the first folder containing CSV files
folder_path1 = 'Generators_variability/test_folder'

# Path to the second folder containing CSV files
folder_path2 = 'Generators_variability'

# List of specific columns to replace in the first set of CSV files
columns_to_replace = ['TRE_WEST_landbasedwind_class1_moderate_1', 'TRE_WEST_landbasedwind_class1_moderate_2', 'TRE_WEST_landbasedwind_class1_moderate_3', 'TRE_landbasedwind_class1_moderate_4', 'TRE_landbasedwind_class1_moderate_5', 'TRE_landbasedwind_class1_moderate_6', 'TRE_WEST_utilitypv_class1_moderate_1', 'TRE_WEST_utilitypv_class1_moderate_2', 'TRE_WEST_utilitypv_class1_moderate_3', 'TRE_utilitypv_class1_moderate_4', 'TRE_utilitypv_class1_moderate_5']

# Iterate through each CSV file in the first folder
for file_name in os.listdir(folder_path1):
    if file_name.endswith('.csv'):
        file_path1 = os.path.join(folder_path1, file_name)
        file_path2 = os.path.join(folder_path2, file_name)
        
        # Read the first and second CSV files
        df1 = pd.read_csv(file_path1)
        df2 = pd.read_csv(file_path2)
        
        # Replace data in specific columns in the first CSV file with data from the second CSV file
        for column in columns_to_replace:
            df1[column] = df2[column]
        
        # Save the updated CSV file
        df1.to_csv(file_path1, index=False)

print('All files processed.')        
