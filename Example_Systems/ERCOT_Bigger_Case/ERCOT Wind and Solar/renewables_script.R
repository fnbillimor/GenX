###########################
####  ###
####  ###
##   ##      RENEWABLES.NINJA
#####       WEBSITE AUTOMATOR
##
#
#  simple instructions:
#    change any file paths in this script from './path/to/' to the directory where you saved the R and CSV files
#    change the token string to match that from your user account
#    run through the five simple examples below
#




#####
## ##  MODEL SETUP
#####

# pre-requisites
library(curl)
library(profvis)
source('./ninja_automator.r')

# insert your API authorisation token here
#token = 'a85c3342758c12e8a306d0d849bced5be1a7d649' #bharat govil
token = 'b26c00672f32c1363a4ccbce0872657ec732059a' #jesse jenkins
# establish your authorisation
h = new_handle()
handle_setheaders(h, 'Authorization'=paste('Token ', token))

# User Input Variables

# Coordinates:
coords = read.csv('wind_solar_locations.csv')
wind_lat = coords$Lat[coords$Wind == 1]
wind_lon = coords$Lon[coords$Wind == 1]

solar_lat = coords$Lat[coords$Solar == 1]
solar_lon = coords$Lon[coords$Solar == 1]

# Years:
year_csv = read.csv("years.csv")
years = year_csv$year
# Wind: 
wind_capacity <- 1 # (kW)
hub_height <- 90 # (m)
turbine_model <- "Vestas+V110+2000"

# Solar:
solar_capacity <- 1 # (kW)
system_loss <- 0.1 # (fraction)
tracking <- 1 # (0 = None, 1 = Azimuth, 2 = Tilt and Azimuth)
tilt <- 35 # (degrees)
azimuth <- 180 # (degrees)


total_count <- 0
wind_count <- length(wind_lat)
solar_count <- length(solar_lat)
#####
## ##  DOWNLOAD RENEWABLE TIME SERIES DATA FOR MULTIPLE LOCATIONS
## ##  USING CSV FILES FOR DATA INPUT AND OUTPUT
#####	

# EXAMPLE 4 :::: read a set of wind farms from CSV - save their outputs to CSV
#                this is the same as example 3 - the UK capital cities
#    your csv must have a strict structure: one row per farm, colums = lat, lon, from, to, dataset, capacity, height, turbine - and optionally name (all lowercase!)

for (i in years){
  wind_from = paste("01/01/", as.character(i), sep="")
  wind_to = paste("31/12/", as.character(i), sep="")
  
  z = ninja_aggregate_wind(wind_lat, wind_lon, wind_from, wind_to, "merra2", wind_capacity, hub_height, turbine_model)
  path <- paste('renewables.ninja.wind.output', as.character(i), '.csv', sep="")
  
  write.csv(z, path, row.names=FALSE)
  cat(path, "has been downloaded\n")
  total_count = total_count + wind_count
  if(floor((total_count + wind_count)/6)  > floor(total_count / 6))
  {
    writeLines("Waiting for 1 minute- 6 Downloads per minute reached")
    pause(60)
    writeLines("1 minute is up!")
  }
  if(floor((total_count + wind_count)/50)  > floor(total_count / 50))
  {
    writeLines("Waiting for 60 minutes- 50 Downloads per hour reached")
    pause(3600)
    writeLines("60 minutes are up!")
  }
}


# EXAMPLE 5 :::: read a set of solar farms from CSV - save their outputs to CSV
#                this is the ten largest US cities - and uses the 'name' column to identify our farms
#    your csv must have a strict structure: one row per farm, colums = lat, lon, from, to, dataset, capacity, system_loss, tracking, tilt, azim - and optionally name (all lowercase!)

for (i in years){
  solar_from = paste("01/01/", as.character(i), sep="")
  solar_to = paste("31/12/", as.character(i), sep="")
  
  z = ninja_aggregate_solar(solar_lat, solar_lon, solar_from, solar_to, "merra2", solar_capacity, system_loss, tracking, tilt, azimuth, name= rep("placeholder", times = length(solar_lat)))
  path <- paste('renewables.ninja.solar.output', as.character(i), ".csv", sep="")
  
  write.csv(z, path, row.names=FALSE)
  cat(path, "has been downloaded\n")
  total_count = total_count + solar_count
  if(floor((total_count + solar_count)/6)  > floor(total_count / 6))
  {
    writeLines("Waiting for 1 minute- 6 Downloads per minute reached")
    pause(60)
  }
  if(floor((total_count + solar_count)/50)  > floor(total_count / 50))
  {
    writeLines("Waiting for 60 minutes- 50 Downloads per hour reached")
    pause(3600)
  }
}


# now you know the way of the ninja
# use your power wisely
# fight bravely