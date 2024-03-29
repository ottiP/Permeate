### Generate data
globalVariables(c("::", "N.sim", "filepath"))



###
#' Main function
#'
#' This function creates the simulated data for each dataset and computes power and type I error using three methods: bonfT, minP, and varP
#' @param setting_name name of the setting to be simulated, correlation of the outcomes, and directory where to store results
#'@import dplyr
#'@import stats
#'@import bindata
#'@importFrom utils stack
#'@importFrom pbapply pbreplicate
#'@importFrom pbapply pblapply
#'@importFrom plyr raply
#'@importFrom dqrng dqsample.int
#'@importFrom plyr llply
#'@importFrom matrixStats colSds
#' @return This function returns the power and type I error using the varP, minP, and bonfT methods
#' @export
main_run<-function(setting,setting_name,corr,dir){
  ### set setting
  #setting <-set_setting(setting_name)
  ### specify path where to save results
  filepath<-paste0(dir,setting_name,"cor",corr,".RDS")
  ### Step 1: generate the simulated data
  sim.data.p <- pbreplicate(setting$N.sim, gen_data_corr(setting$RR,setting$prop.outcome,setting$N1,setting$N2,setting$N.outcomes,corr), simplify=F)
  sim.data.t <- pbreplicate(setting$N.sim, gen_data_corr(RR=rep(1,length(setting$RR)),setting$prop.outcome,setting$N1,setting$N2,setting$N.outcomes, corr), simplify=F)
  options(future.rng.onMisuse="ignore")
  ### Repeat permutation for 999 times
  N.permute = 999
  ### Precompute permutations for better performance
  permute = raply(
    N.permute,
    # random shuffled array of N1 unvax (FALSE) and N2 vax (TRUE)
    c(rep(FALSE,setting$N1), rep(TRUE,setting$N2))[dqsample.int(setting$N1 + setting$N2)]
  )
  ### Step 2: run the methods to compute power and type 1 error
  d.perm.p <- llply(sim.data.p, perm_fun, permute=permute,N.outcomes=setting$N.outcomes,.parallel=TRUE)
  d.perm.t <- llply(sim.data.t, perm_fun, permute=permute,N.outcomes=setting$N.outcomes,.parallel=TRUE)
  r.p<-as.data.frame(compute_power(d.perm.p,setting$N.sim))
  r.t<-as.data.frame(compute_power(d.perm.t,setting$N.sim))
  r<-list("Power"=r.p,"Type I error"=r.t)
  ### Save the results
  saveRDS(r,file=filepath)
  return(r)
}

###
#' The user can specify the settings that will be run. Either the user specifies a setting based on real-world clinical trials or uses custom parameters
#' @param setting name of the setting to be simulated, if "custom", the user can specify the number of simulated datasets, number of outcomes, risk ratio, incidence of the outcomes
#' and number of individuals in control and treatment groups
#' @return This function returns the setting's characteristics that will be the input in the main function
#' @export
set_setting <- function(setting,N.sim=FALSE,N.outcomes=FALSE,RR=FALSE,prop.outcome=FALSE,N1=FALSE,N2=FALSE){
  if(setting=="setting1"){ ### This corresponds to scenario 1 in the paper
    return(list(N.sim=1000,N.outcomes=3,RR=c(0.60,0.60,0.70),prop.outcome=c(0.22,0.20,0.12),N1=200,N2=200))
  }
  else if(setting=="setting2"){
    return(list(N.sim=1000,N.outcomes=3,RR=c(0.25,0.4,0.6),prop.outcome=c(.05,.02,.03),N1=496,N2=994))
  }
  else if(setting=="setting3"){
    return(list(N.sim=1000,N.outcomes=3,RR=c(0.60,0.55,0.5),prop.outcome=c(.02,.04,.01),N1=1430,N2=2765))
  }
  else if(setting=="custom"){
    return(list(N.sim=N.sim,N.outcomes=N.outcomes,RR=RR,prop.outcome=prop.outcome,N1=N1,N2=N2))
  }
  else(print("Please specify setting for data simulation"))
}

#' Generate simulated data
#'
#' This function creates simulated correlated data. It creates both the treatment and control groups
#' with N.outcomes endpoints with certain correlation speficied by the user
#'
#' @param RR Params are risk ratio, incidence of outcomes, N subjects in both groups, number of outcomes and correlation among outcomes
#' @return The simulated data
#' @export
gen_data_corr <- function(RR,prop.outcome,N1, N2, N.outcomes, cor){
  sigma <- matrix(cor,N.outcomes,N.outcomes); diag(sigma)=1
  ## Simulate 10000 x-y pairs, and check that they have the specified
  ## correlation structure
  prob.Y1 <- prop.outcome
  Y1 <- bindata::rmvbin(N1, margprob = prob.Y1, sigma = sigma)
  Y2 <- bindata::rmvbin(N2, margprob = prob.Y1*RR, sigma = sigma)
  N.unvax <- nrow(Y1)
  N.vax <- nrow(Y2)
  out.data=list('Y1'=Y1,'Y2'=Y2,'N.unvax'=N.unvax,'N.vax'=N.vax)
  return(out.data)
}

###
#' Run permutation and naive functions
#'
#' This function takes the simulated data and computes the test statistics using permutation approaches
#' @param ds the simulated data and a matrix permute to indicate the permuted indeces
#' @return P-values from each method
#' @export
perm_fun <- function(ds, permute,N.outcomes){
  Y = rbind(ds$Y1, ds$Y2)

  # Y: RxC observation matrix
  # permute: NxR permutation matrix. permute[n, r] is TRUE if row r is vaxed in permutation n
  # permute %*% Y = NxC matrix. [n, c] = column sum of c column of vaxed rows of Y in permutation n
  N.vax.outcome = permute %*% Y
  N.unvax.outcome = (!permute) %*% Y

  # Check if any row in N.vax.outcome contains zero and add 0.5 to the entire row if true
  has_zero_row <- apply(N.vax.outcome == 0, 1, any)
  has_zero_row_unvax <- apply(N.unvax.outcome == 0, 1, any)
  N.vax.outcome[has_zero_row, ] <- N.vax.outcome[has_zero_row, ] + 0.5
  N.unvax.outcome[has_zero_row, ] <- N.unvax.outcome[has_zero_row, ] + 0.5
  N.vax.outcome[has_zero_row_unvax, ] <- N.vax.outcome[has_zero_row_unvax, ] + 0.5
  N.unvax.outcome[has_zero_row_unvax, ] <- N.unvax.outcome[has_zero_row_unvax, ] + 0.5

  N.vax <- matrix(ds$N.vax,nrow=nrow(N.vax.outcome),ncol=ncol(N.vax.outcome))
  N.unvax <- matrix(ds$N.unvax,nrow=nrow(N.vax.outcome),ncol=ncol(N.vax.outcome),byrow=TRUE)

  N.unvax[has_zero_row, ] <- N.unvax[has_zero_row, ] + 1
  N.vax[has_zero_row, ] <- N.vax[has_zero_row, ] + 1
  N.unvax[has_zero_row_unvax, ] <- N.unvax[has_zero_row_unvax, ] + 1
  N.vax[has_zero_row_unvax, ] <- N.vax[has_zero_row_unvax, ] + 1

  RR <- ((N.vax.outcome)/(N.vax))/((N.unvax.outcome)/(N.unvax)) ## +0.5 for vax and +1 for N.vax

  ### Load function with results from bonf, p_min_obs and p_avg_obs
  prop_t<-bonf_t(ds,N.outcomes)

  ### Compute test statistics over observed data
  t.obs <- test_statistics_obs(ds)

  ### Compute weighted perm  with 1/var as weight
  RR.log<-log(RR)
  Var_RR<-(((1/N.vax.outcome)+(1/N.unvax.outcome))-((1/ds$N.vax)+(1/ds$N.unvax))) ## +0.5 for vax and +1 for N.vax
  SE_RR<-sqrt(Var_RR)
  w.j <- (1/Var_RR)/rowSums(1/Var_RR)
  RR_w_V<-rowSums(RR.log*w.j)

  ### P_value weighted
  sig.w.V  <- 1-mean(RR_w_V > t.obs$Obs.w.V,na.rm = TRUE)

  ### compute p value for each RR and take the min
  min.RR <- apply(RR,1, min)

  # Implement minP method taking both min and avg
  p_value <- matrix(NA,nrow=nrow(N.vax.outcome),ncol=N.outcomes)
  p_value<-mapply(prop_test,asplit(N.vax.outcome,1),asplit(N.unvax.outcome,1),MoreArgs=list(ds$N.vax,ds$N.unvax,N.outcomes))
  p_value_min <- apply(p_value,2,min)
  sig.min.p  <- 1-mean(p_value_min>prop_t$p_min_obs,na.rm = TRUE)
  #### P-value from Bonf
  bonft <- prop_t$p_dec
  #### Compute power for each outcome as status quo
  out.v <- c(sig.w.V,sig.min.p,bonft)
  return(out.v)

}

###
#' Test statistics observed data
#'
#' This function computes the test statistics of the observed data
#' @param ds the simulated data, N.outcomes the number of outcomes
#' @return Observed test statistics
#' @export
test_statistics_obs <- function(ds,N.outcomes){

  ### Observed data
  Obs.unvax.events <- colSums(ds$Y1)
  Obs.vax.events <- colSums(ds$Y2)
  N.vax = nrow(ds$Y2)
  N.unvax = nrow(ds$Y1)

  if(any(Obs.vax.events==0)){
    Obs.unvax.events = Obs.unvax.events+0.5
    Obs.vax.events = Obs.vax.events+0.5
    N.vax = N.vax +1
    N.unvax = N.unvax +1
  }

  if(any(Obs.unvax.events==0)){
    Obs.unvax.events = Obs.unvax.events+0.5
    Obs.vax.events = Obs.vax.events+0.5
    N.vax = N.vax +1
    N.unvax = N.unvax +1
  }

  Obs.RR <- (Obs.vax.events/ds$N.vax)/(Obs.unvax.events/ds$N.unvax) ## +0.5 for vax and +1 for N.vax

  ### Compute test statistics 1: weighted average
  Var_RR <- (1/Obs.vax.events+1/Obs.unvax.events)-(1/N.vax+1/N.unvax) ## +0.5 for vax and +1 for N.vax
  w.j <- (1/Var_RR)/sum(1/Var_RR)
  Obs.w.V <-sum(log(Obs.RR)*w.j)

  ### Compute test statistics 2: take the min
  Obs.min <- min(Obs.RR)
  out.obs <- list("Obs.w.V"=Obs.w.V,"Obs.min"=Obs.min)
  return(out.obs)
}

###
#' Proportion test
#'
#' This function computes prop_test and stores the p-values
#' @param N.vax.outcomes the number of cases in the treatment group, in the control group, the total number of people in treatment and control
#' groups and the total number of outcomes
#' @return P-values from prop test
#' @export
prop_test <- function(N.vax.outcomes,N.unvax.outcomes,N.vax,N.unvax,N.outcomes){
  p_value <- rep(NA,times=N.outcomes)
  ### Compute Bonferroni using prop.test function
  #p_test <- prop.test(x=c(N.vax.outcomes,N.unvax.outcomes),n=c(ds$N.vax,ds$N.unvax),alternative = 'less')
  mat<-t(rbind(N.vax.outcomes,N.unvax.outcomes))
  p_test<-apply(mat,1,prop.test,n=c(N.vax,N.unvax),alternative = 'less')
  p_value<-unlist(lapply(p_test,function(x) x$p.value))
  return(p_value)
}

###
#' Naive method
#'
#' This function uses prop.test and implements Bonferroni test
#' @param ds the simulated data and the total number of outcomes
#' @return P-values from each method
#' @export
bonf_t <- function(ds,N.outcomes){
  N.unvax.outcomes <- colSums(ds$Y1)
  N.vax.outcomes <- colSums(ds$Y2)
  if(any(N.vax.outcomes==0)){
    N.unvax.outcomes = N.unvax.outcomes+0.5
    N.vax.outcomes = N.vax.outcomes+0.5
    ds$N.vax = ds$N.vax +1
    ds$N.unvax = ds$N.unvax +1
  }

  if(any(N.unvax.outcomes==0)){
    N.unvax.outcomes = N.unvax.outcomes+0.5
    N.vax.outcomes = N.vax.outcomes+0.5
    ds$N.vax = ds$N.vax +1
    ds$N.unvax = ds$N.unvax +1
  }


  #####
  p_value <- prop_test(N.vax.outcomes,N.unvax.outcomes,ds$N.vax,ds$N.unvax,N.outcomes)
  p_value_min <- min(p_value) ### save this value for minP test
  p_value_avg <- mean(p_value) ### save this value for avgP test
  ### Compute Bonferroni
  p_dec <- mean(p_value_min<0.05/N.outcomes)
  ### Compute Bonferroni using CI
  #CI_upper <- CI_function(ds,N.vax.outcomes,N.unvax.outcomes,N.outcomes,bonf=TRUE)
  #RR_dec <- max(ifelse(CI_upper<1,1,0),na.rm = TRUE)
  result<- list("p_min_obs"=p_value_min,"p_avg_obs"=p_value_avg,"p_dec"=p_dec)
  return(result)
}

###
#' Power and type I error
#'
#' This function computes the power and the type I error from each method
#' @param l.result p-values from each dataset and method
#' @return Power and type I error from each method
#' @export
compute_power<-function(l.result,N.sim){
  m.result <- do.call(rbind,l.result)
  power<-rep(0,times=ncol(m.result))
  SE<-rep(0,times=ncol(m.result))
  alpha<-0.05
  power[1:2]<-colMeans(m.result[,1:2]<alpha,na.rm = TRUE)
  power[3]<-mean(m.result[,3])
  SE[1:2]<-colSds(1*(m.result[,1:2]<alpha),na.rm=TRUE)/sqrt(N.sim)
  SE[3] <- sd(m.result[,3])/sqrt(N.sim)
  result<-rbind(power*100,SE*100)
  colnames(result)<-c("varP","minP","bonfT")
  return(result)
}

###
#' Plotting function
#'
#' This function manipulates the results for plotting
#' @param path where the results are stored, and specific pattern to load correct results
#' @return A dataframe for plotting
#' @export
load_result <- function(path,pattern){
  file_list <- list.files(path=path, pattern=(pattern))
  test1 <-
    all.res <-
    pblapply(file_list, function(x){
      print(x)
      path1 <- paste0(path,x)
      test1 <- readRDS(path1)
    })
  power <- bind_rows(sapply(test1,`[`, "Power")) #combine power
  power<-stack(power)
  power.se <- power %>% dplyr::filter(row_number() %% 2 == 0) ## Select even rows
  power.e <- power %>% dplyr::filter(row_number() %% 2 == 1) ## Select odd rows
  typeone <- bind_rows(sapply(test1,`[`, "Type I error")) #combine type1 error
  typeone<-stack(typeone)
  typeone.se <- typeone %>% dplyr::filter(row_number() %% 2 == 0) ## Select even rows
  typeone.e <- typeone %>% dplyr::filter(row_number() %% 2 == 1) ## Select odd rows
  power.l <- power.e
  power.l$values <- power.e$values-1.96*power.se$values
  power.u <- power.e
  power.u$values <- power.e$values+1.96*power.se$values
  typeone.l <-typeone.e
  typeone.l$values <- typeone.e$values-1.96*typeone.se$values
  typeone.u <- typeone.e
  typeone.u$values <- typeone.e$values+1.96*typeone.se$values
  power.df<-as.data.frame(cbind(power.e,power.l$values,power.u$values))
  typeone.df<-as.data.frame(cbind(typeone.e,typeone.l$values,typeone.u$values))
  colnames(power.df)<-c("estimate","model","lower","upper")
  colnames(typeone.df)<-c("estimate","model","lower","upper")
  result<-list("power.df"=power.df,"typeone.df"=typeone.df)
  return(result)
}

