# ------------------------------------------------------------------------------
# Predicting Modelling for Batting Data
#
#
# ------------------------------------------------------------------------------


# Lib
suppressPackageStartupMessages(library(data.table))
suppressPackageStartupMessages(library(dplyr))
suppressPackageStartupMessages(library(lubridate))
suppressPackageStartupMessages(library(foreach))
suppressPackageStartupMessages(library(doParallel))
suppressPackageStartupMessages(library(stringr))

suppressPackageStartupMessages(library(h2o))


# Core Parameters
n_seed = 1234 # for reproducibility


# ------------------------------------------------------------------------------
# Start H2O
# ------------------------------------------------------------------------------

h2o.init(nthreads = -1, max_mem_size = "8g")



# ------------------------------------------------------------------------------
# Load Munged Datasets from 'data_munging.R'
# ------------------------------------------------------------------------------


# Load reformatted data
d_train = fread("C:/Users/Adam/Documents/GitHub/moneyball/cache_data/Wrangled_data/d_bat_train.csv")
d_valid = fread("C:/Users/Adam/Documents/GitHub/moneyball/cache_data/Wrangled_data/d_bat_valid.csv")
d_test = fread("C:/Users/Adam/Documents/GitHub/moneyball/cache_data/Wrangled_data/d_bat_test.csv")


# (Temp) Add Full Name for quick sort
d_train$full_name = paste(d_train$nameFirst, d_train$nameLast)
d_valid$full_name = paste(d_valid$nameFirst, d_valid$nameLast)
d_test$full_name = paste(d_test$nameFirst, d_test$nameLast)


d_all = rbind(d_train, d_valid, d_test)
d_all = as.data.table(d_all)
d_all = d_all[yearID >= 2010]
d_all_with_pred = copy(d_all)



# ------------------------------------------------------------------------------
# Define Targets and Features for Supervised Learning
# ------------------------------------------------------------------------------


# Targets (looks at six main metrics for batting)
targets = c("BA",
            "OBP",
            "SLG",
            "HR",
            "RBI",
            "SO")


# Features
features = setdiff(colnames(d_train),
                   c("playerID",
                     "nameFirst", "nameLast", "nameGiven", "full_name",
                     colnames(d_train)[17:37]))

print(features)

# Main AutoML Loop
for (n_target in 1:length(targets)) {


  # Display
  cat("\n[H2O AutoML]: Building Models for Target ...", targets[n_target], "...\n")

  # Clean up H2O cluster
  h2o.removeAll()

  # Filter
  d_train = copy(d_all[yearID >= 2010 & yearID <= 2015])
  d_valid = copy(d_all[yearID >= 2016 & yearID <= 2017])
  d_test = copy(d_all[yearID > 2017])


  # H2O data frame
  h_train = as.h2o(d_train, destination_frame = "h_train")
  h_valid = as.h2o(d_valid, destination_frame = "h_valid")
  h_test = as.h2o(d_test, destination_frame = "h_test")
  h_all = as.h2o(d_all, destination_frame = "h_all")


  # H2O AutoML with Lahman only
  automl_lahman = h2o.automl(x = features,
                             y = targets[n_target],
                             training_frame = h_train,
                             validation_frame = h_valid,
                             max_models = 10, # increase this to allow more models
                             max_runtime_secs = 120, # increase this to allow more time
                             stopping_metric = "RMSE",
                             stopping_rounds = 3,
                             seed = n_seed,
                             exclude_algos = c("DeepLearning"), # you can exclude any algo
                             project_name = paste0("AutoML_Lahman", targets[n_target]))


  # Extract model
  model_best_lahman = automl_lahman@leader
  # print(automl_lahman@leaderboard)


  # Make predictions for all records in one go
  tmp_yhat_lahman = as.data.frame(h2o.predict(model_best_lahman, h_all))


  # Store Results
  colnames(tmp_yhat_lahman) = paste0("pred_lahman_", targets[n_target])
  d_all_with_pred = cbind(d_all_with_pred, tmp_yhat_lahman)


}


# Sort (full data frame with predictions) - Final Table
d_all_with_pred = d_all_with_pred %>% arrange(playerID, yearID)
head(d_all_with_pred)

prediction_folder = "C:/Users/Adam/Documents/GitHub/moneyball/cache_data/Predictions/"
fileName = paste(prediction_folder, 'all_with_pred_batting.csv')
write.csv(d_all_with_pred,fileName)

metrics1 <- as.data.frame( model_best_lahman, n = nrow( model_best_lahman)) 
# Output Example
# print(d_all_with_pred %>% filter(full_name == "Mike Trout"))
library(ggplot2)
graph = ggplot(d_all_with_pred, aes(x= yearID, y = BA)) +
  geom_line(lwd=1.05) + geom_point(size=2.5) + 
  ggtitle("preds (01/2010 to 05/2017)") +
  xlab("Date") + ylab("Batting Average") +
  theme(legend.title=element_blank()) + xlab(" ") + 
  theme(axis.text.x=element_text(colour="black")) +
  theme(axis.text.y=element_text(colour="black")) +
  theme(legend.position=c(.4, .85))

graph_2 = ggplot(d_all) +
  geom_histogram() + 
  ggtitle("Actual (01/2010 to 05/2017)") +
  xlab("Date") + ylab("Batting Average") +
  theme(legend.title=element_blank()) + xlab(" ") + 
  theme(axis.text.x=element_text(colour="black")) +
  theme(axis.text.y=element_text(colour="black")) +
  theme(legend.position=c(.4, .85))
