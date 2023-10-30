## Compile Texas ERCOT demand data - 2002-2019
## Data source: http://www.ercot.com/gridinfo/load/load_hist/

## Data cleaning note: there was one missing hour of data in 2016 file, 2016-11-07 00:00:00
## I filled in missing data point by interpolating adjacent hours.

library("readxl") #for reading .xsl and .xlsx files

path <- "/Users/jdj2/Dropbox (Princeton)/ZMC electricity market challenges/01 - Collab with Jacob Mays/Data/ERCOT Demand/"
DEMAND <- data.frame(Year = numeric(0), Hour_Index = numeric(0), Hour_End = character(0), Date = character(0),
                     Raw_Demand_MW = numeric(0), Demeaned_Demand = numeric(0))

for(year in 2002:2019){
  if(year <= 2015){ extension = ".xls"} else {extension = ".xlsx"}
  DATA <- read_excel(paste0(path, "Demand_by_Year/", year, "_ERCOT_Hourly_Load_Data", extension))
  TEMP <- data.frame(Year = rep(year,nrow(DATA)),
                     Hour_Index = c(1:nrow(DATA)),
                     Hour_End = matrix(unlist(strsplit(as.character(DATA$Hour_End), " ")), ncol=2, byrow=T)[,2], 
                     Date = matrix(unlist(strsplit(as.character(DATA$Hour_End), " ")), ncol=2, byrow=T)[,1],
                     Raw_Demand_MW = DATA$ERCOT,
                     Demeaned_Demand_MW = DATA$ERCOT - mean(DATA$ERCOT, na.rm=T)
                     )
  DEMAND <- rbind(DEMAND, TEMP)                  
}

write.csv(DEMAND, paste0(path,"ERCOT_demand_2002_2019.csv"))

# Explore time trends:
TRENDS <- data.frame(Year = c(2002:2019), 
                     Mean = numeric(length(c(2002:2019))),
                     Variance = numeric(length(c(2002:2019)))
                     )
for(y in 1:nrow(TRENDS)){ 
  TRENDS$Mean[y] <- mean(DEMAND[DEMAND$Year==TRENDS$Year[y],]$Raw_Demand_MW) 
  TRENDS$Variance[y] <- var(DEMAND[DEMAND$Year==TRENDS$Year[y],]$Demeaned_Demand_MW) 
}

plot(y=TRENDS$Mean, x=TRENDS$Year, col="red")
plot(y=TRENDS$Variance, x=TRENDS$Year, col="blue")

plot(x=DEMAND[DEMAND$Year==2019,]$Hour_Index, y=DEMAND[DEMAND$Year==2019,]$Demeaned_Demand_MW, col="blue", type="l")
lines(x=DEMAND[DEMAND$Year==2002,]$Hour_Index, y=DEMAND[DEMAND$Year==2002,]$Demeaned_Demand_MW, col="red")

plot(x=1:nrow(DEMAND), y=DEMAND$Demeaned_Demand_MW, col="blue", type="l")