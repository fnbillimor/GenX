## Compile Texas Wind and Solar demand data - 2002-2019
## Data source: https://www.renewables.ninja/
## See wind_solar_locations.csv for lat/long for each site and 
## wind_solar_settings for wind turbine and solar system inputs for renewables.ninja

path <- "/Users/jdj2/Dropbox (Princeton)/ZMC electricity market challenges/01 - Collab with Jacob Mays/Data/ERCOT Wind and Solar/"
windpath <- paste0(path,"Wind_2002-2019")
solarpath <- paste0(path,"Solar_2002-2019")

# Create data frame for wind & solar data
# Four profiles reflecting average of 3 individual renewables.ninja profiles each:
# 1. Interior wind (wind profiles 1-3); 2. Coastal wind (wind profiles 4-6); 
# 3. Solar PV (PV profiles 1-3) in DC rated capacity terms; 
# 4. Solar PV (PV profiles 1-3) in AC rated capacity terms assuming 10% system losses and 1.33:1 DC:AC ratio
RE <- data.frame(Year = numeric(0), Hour_Index = numeric(0), 
                 Interior_Wind = numeric(0), Coastal_Wind = numeric(0),
                 Solar_PV_DC = numeric(0), Solar_PV_AC = numeric(0))
# Read wind and solar time series data and compile RE data frame
for(y in 2002:2019){
  WIND <- read.csv(paste0(windpath, "/renewables.ninja.wind.output",y,".csv"), stringsAsFactors=F)
  SOLAR <- read.csv(paste0(solarpath, "/renewables.ninja.solar.output",y,".csv"), stringsAsFactors=F)
  h <- nrow(WIND)
  # Create AC adjusted profiles for solar PV. AC = Min(DC/(1-L)*R*(1-L), 1.0) 
  # where L is the system losses (10%) and R is the AC:DC ratio (1.33). 
  # Note: by default, renewables.ninja assumes DC capacity = AC inverter capacity and DC-AC losses are 10%
  # See https://github.com/renewables-ninja/gsee/blob/master/gsee/pv.py
  # So adjusting here to standard utility scale PV system configurations for US 
  # with 1.33:1 DC:AC ratio as per https://emp.lbl.gov/sites/default/files/lbnl_utility_scale_solar_2019_edition_final.pdf (p. ii)
  L = 0.1
  R = 1.33
  SOLAR$AC1 <- SOLAR$placeholder/(1-L)*R*(1-L)
  SOLAR$AC2 <- SOLAR$placeholder.1/(1-L)*R*(1-L)
  SOLAR$AC3 <- SOLAR$placeholder.2/(1-L)*R*(1-L)
  SOLAR[SOLAR$AC1>1,]$AC1 = 1.0
  SOLAR[SOLAR$AC2>1,]$AC2 = 1.0
  SOLAR[SOLAR$AC3>1,]$AC3 = 1.0
  RE <- rbind(RE, data.frame(Year = rep(y,h), Hour_Index = c(1:h), 
                     Interior_Wind = (WIND$outputV1+WIND$outputV2+WIND$outputV3)/3, 
                     Coastal_Wind = (WIND$outputV4+WIND$outputV5+WIND$outputV6)/3, 
                     Solar_PV_DC = (SOLAR$placeholder+SOLAR$placeholder.1+SOLAR$placeholder.2)/3,
                     Solar_PV_AC = (SOLAR$AC1+SOLAR$AC2+SOLAR$AC3)/3
                     ))
}

write.csv(RE, paste0(path,"/ERCOT_renewables_2002_2019.csv"))

