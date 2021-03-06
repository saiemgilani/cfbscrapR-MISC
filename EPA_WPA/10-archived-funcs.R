prep_df_epa <- function(dat) {
  # This function is used to calculate the EP - after the play
  # Then EPA = EP_After - EP_Before
  # Provide, this function so people can calcualte
  # EPA on new games in 2019 szn
  # after which they can feed that to the WPA model
  turnover_play_type = c(
    'Fumble Recovery (Opponent)',
    'Pass Interception Return',
    'Interception Return Touchdown',
    'Fumble Return Touchdown',
    'Safety',
    'Interception',
    'Pass Interception'
  )
  
  off_TD = c('Passing Touchdown','Rushing Touchdown')
  def_TD = c('Interception Return Touchdown','Fumble Return Touchdown','Punt Return Touchdown',
             'Fumble Recovery (Opponent) Touchdown')
  
  dat = dat %>%
    mutate_at(vars(clock.minutes, clock.seconds), ~ replace_na(., 0)) %>%
    mutate(
      clock.minutes = ifelse(period %in% c(1, 3), 15 + clock.minutes, clock.minutes),
      raw_secs = clock.minutes * 60 + clock.seconds,
      # coef = home_team == defense,
      # yards_to_goal = 100 * (1 - coef) + (2 * coef - 1) * yard_line,
      # log_ydstogo = log(distance),
      half = ifelse(period <= 2, 1, 2),
      new_yardline = 0,
      new_Goal_To_Go = FALSE,
      new_down = 0,
      new_distance = 0,
      turnover = 0
    ) %>%
    left_join(team_abbrs_df,by=c("offense"="full_name")) %>%
    left_join(team_abbrs_df,by=c("defense"="full_name"),suffix=c("_offense","_defense"))
  
  # Turnover Index
  turnover_ind = dat$play_type %in% turnover_play_type
  dat[turnover_ind, "new_down"] = 1
  dat[turnover_ind, "new_distance"] = 10
  dat[turnover_ind, "turnover"] = 1
  # First down
  first_down_ind = str_detect(dat$play_text, '1ST')
  dat[first_down_ind, "new_down"] = 1
  dat[first_down_ind, "new_distance"] = 10
  dat[first_down_ind, "new_yardline"] = dat[first_down_ind,"yards_to_goal"] - dat[first_down_ind,"yards_gained"]
  
  # these mess up when you have to regex the yardline, so remove em
  dat$play_text = gsub("1ST down","temp",dat$play_text)
  dat$play_text = gsub("2ND down","temp",dat$play_text)
  dat$play_text = gsub("3RD down","temp",dat$play_text)
  dat$play_text = gsub("4TH down","temp",dat$play_text)
  
  
  # Otherwise What happened?
  dat[(!turnover_ind &
         !first_down_ind), "new_down"] = dat[(!turnover_ind &
                                                !first_down_ind), "down"] + 1
  dat[(!turnover_ind &
         !first_down_ind), "new_distance"] = dat[(!turnover_ind &
                                                    !first_down_ind), "distance"] - dat[(!turnover_ind &
                                                                                           !first_down_ind), "yards_gained"]
  dat[(!turnover_ind & !first_down_ind),"new_yardline"] =  dat[(!turnover_ind &
                                                                  !first_down_ind), "yards_to_goal"] - dat[(!turnover_ind &
                                                                                                              !first_down_ind), "yards_gained"]
  
  opp_fumb_rec = dat$play_type=="Fumble Recovery (Opponent)"
  dat[opp_fumb_rec, "new_down"] = 1
  dat[opp_fumb_rec, "new_distance"] = 10
  dat[opp_fumb_rec, "new_yardline"] = 100 - (dat[opp_fumb_rec, "yard_line"] +
                                               dat[opp_fumb_rec, "yards_gained"])
  sack = str_detect(dat$play_type, "Sack")
  if(any(sack)){
    dat[sack, "new_yardline"] = (dat[sack, "yards_to_goal"] - dat[sack, "yards_gained"])
    dat[sack, "new_down"] = dat[sack, "down"] + 1
    dat[sack, "new_distance"] = dat[sack, "distance"] - dat[sack, "yards_gained"]
    
    ## sack and fumble, this seems to be weirdly tricky
    sack_fumble = sack & (str_detect(dat$play_text,"fumbled"))
    if(any(sack_fumble)){
      dat[sack_fumble,"play_text"] = sapply(dat[sack_fumble,"play_text"],function(x){
        gsub("return.*","",x)
      })
      # gsub("return.*","",dat[sack_fumble,"play_text"])
      q = as.numeric(stringi::stri_extract_last_regex(dat$play_text[sack_fumble],"\\d+"))
      # now identify, if you need to subtract 100?
      receovered_string = str_extract(dat$play_text[sack_fumble], '(?<=, recovered by )[^,]+')
      dat[sack_fumble,"coef"] = gsub("([A-Za-z]+).*", "\\1",receovered_string)
      inds = which(sack_fumble)
      dat[sack_fumble,"new_down"] = unlist(sapply(inds,function(x){
        ifelse(dat[x,"abbreviation_offense"] == dat[x,"coef"],
               dat[x,"new_down"],1)
      }))
      
      dat[sack_fumble,"new_yardline"] = abs(
        ((1-!(dat[sack_fumble,"coef"] == dat[sack_fumble,"abbreviation_defense"])) * 100) - q
      )
    }
  }
  
  safety = dat$play_type == 'Safety'
  if(any(safety)){
    dat[safety,"new_yardline"] = 99
  }
  
  
  off_td_ind = dat$play_type %in% off_TD
  if(any(off_td_ind)){
    dat[off_td_ind,"new_down"] = 1
    dat[off_td_ind,"new_distance"] = 10
  }
  
  #Fake yardline for Offensive tocuhdown play
  temp_inds = (off_td_ind | (dat$play_type %in% def_TD))
  if(any(temp_inds)){
    dat[temp_inds,"new_yardline"] = 99
  }
  
  
  # Turnovers on Down
  tod_ind  = (!off_td_ind) & (dat$new_down>4)
  if(any(tod_ind)){
    dat[tod_ind,"turnover"] = 1
    dat[tod_ind,"new_down"] = 1
    dat[tod_ind,"new_distance"] = 10
    tod_ind = tod_ind & dat$play_type == "Punt"
    dat[tod_ind,"new_yardline"] = 100-dat[tod_ind,"new_yardline"]
  }
  
  ## proper placement of punt
  punt = c("Punt")
  punt_ind = dat$play_type %in% punt
  if(any(punt_ind)){
    punt_play = dat[punt_ind,] %>% pull(play_text)
    double_try = stringi::stri_extract_last_regex(punt_play,'(?<=the )[^,]+')
    q = as.numeric(stringi::stri_extract_last_regex(double_try,"\\d+"))
    dat[punt_ind,"coef"] = gsub("([A-Za-z]+).*", "\\1",double_try)
    dat[punt_ind,"new_yardline"] = abs(((1-(dat[punt_ind,"coef"] == dat[punt_ind,"abbreviation_defense"])) * 100) - q)
  }
  
  # missed field goal, what happens
  miss_fg <- c("Field Goal Missed","Missed Field Goal Return")
  miss_fg_ind = dat$play_type %in% miss_fg
  if(any(miss_fg_ind)){
    dat[miss_fg_ind,"new_down"] = 1
    dat[miss_fg_ind,"new_distance"] = 10
    # if FG is within 20, team gets it at the 20
    # otherwise team gets it at the LOS (add the 17 yards back)
    adj_yds = dat[miss_fg_ind,] %>% pull(yards_to_goal)
    dat[miss_fg_ind,"new_yardline"] = ifelse(adj_yds<=20,80,100 - (adj_yds-17))
  }
  
  # handle missed field goals here
  # just workout the yards here
  miss_fg_return = "Missed Field Goal Return"
  miss_fg_return_ind = dat$play_type == miss_fg_return
  if(any(miss_fg_return_ind)){
    miss_return_play = dat[miss_fg_return_ind,] %>% pull(play_text)
    double_try = stringi::stri_extract_last_regex(miss_return_play,'(?<=the )[^,]+')
    q = as.numeric(stringi::stri_extract_last_regex(double_try,"\\d+"))
    dat[miss_fg_return_ind,"coef"] = gsub("([A-Za-z]+).*", "\\1",double_try)
    dat[miss_fg_return_ind,"new_yardline"] = abs(((1-(dat[miss_fg_return_ind,"coef"] == dat[miss_fg_return_ind,"abbreviation_defense"])) * 100) - q)
  }
  
  # missed field goal return
  block_return <- c("Missed Field Goal Return")
  block_inds = dat$play_type %in% block_return
  if(any(block_inds)){
    dat[block_inds,"new_down"] = 1
    dat[block_inds,"new_distance"] = 10
    dat[block_inds,"new_yardline"] = (100 - dat[block_inds,"yards_to_goal"])  - dat[block_inds,"yards_gained"]
  }
  
  
  # interception return
  int_ret <- c("Pass Interception Return","Blocked Field Goal")
  int_inds = dat$play_type %in% int_ret
  if(any(int_inds)){
    dat[int_inds,"new_down"] = 1
    dat[int_inds,"new_distance"] = 10
    # extract the yardline via regex
    # this sucks but do it
    q = as.numeric(stringi::stri_extract_last_regex(dat$play_text[int_inds],"\\d+"))
    # now identify, if you need to subtract 100?
    temp_team = str_extract_all(dat$play_text[int_inds], team_abbrs_list)
    team_team = unlist(sapply(temp_team,function(x){
      ind = length(x)
      val = x[ind]
      if(length(val)==0){
        return(NA)
      }
      return(val)
    }))
    dat[int_inds,"coef"] = team_team
    dat[int_inds,"new_yardline"] = abs(((1-!(dat[int_inds,"coef"] == dat[int_inds,"abbreviation_defense"])) * 100) - q)
  }
  
  touchback = str_detect(dat$play_text,"touchback")
  dat[touchback,"new_yardline"] = 80
  dat[touchback,"new_down"] = 1
  
  ## deal with penalties as they also throw this off
  penalty = (str_detect(dat$play_text,"Penalty"))
  if(any(penalty)){
    penalty_string = str_extract(dat$play_text[penalty], '(?<=Penalty,)[^,]+')
    double_try = str_extract(penalty_string,'(?<=to the )[^,]+')
    q = as.numeric(stringi::stri_extract_last_regex(double_try,"\\d+"))
    dat[penalty,"coef"] = gsub("([A-Za-z]+).*", "\\1",double_try)
    # first calculate things for regular cases
    dat[penalty,"new_yardline"] = abs(((1-(dat[penalty,"coef"] == dat[penalty,"abbreviation_defense"])) * 100) - q)
  }
  
  declined = penalty & str_detect(dat$play_text,"declined")
  if(any(declined)){
    dat[declined,"new_yardline"] = dat[declined,"yards_to_goal"] - dat[declined,"yards_gained"]
  }
  
  missing_inds = dat$new_distance <= 0
  dat[missing_inds,"new_down"] = 1
  dat[missing_inds,"new_distance"] = 10
  dat[missing_inds,"new_yardline"] = dat[missing_inds,"yards_to_goal"] - dat[missing_inds,"yards_gained"]
  
  fg_good = dat$play_type %in% c("Field Goal Good","Missed Field Goal Return Touchdown")
  if(any(fg_good)){
    # temp hold anyways, we are going to replace the post EPA here with 3
    dat[fg_good,"new_down"] = 1
    dat[fg_good,"new_distance"] = 10
    dat[fg_good,"new_yardline"] = 80
  }
  
  fifty_ydline = str_detect(dat$play_text, "50 yard line")
  dat[fifty_ydline, "new_yardline"] = 50
  
  testing = dat %>% filter(new_yardline<0)
  
  
  ## If 0, reset to 25
  #zero_yd_line = dat$new_yardline == 0
  #dat[zero_yd_line,"new_yardline"] = 25
  
  dat = dat  %>%
    mutate(
      new_Goal_To_Go = ifelse(
        str_detect(play_type, "Field Goal"),
        new_distance <= (new_yardline - 17),
        new_distance <= new_yardline
      ),
      new_TimeSecsRem = lead(TimeSecsRem),
      new_log_ydstogo = log(new_distance))
  
  ## fix NA's log_yds
  blk_fg_na = dat$play_type == "Blocked Field Goal" & is.na(dat$new_log_ydstogo)
  dat$new_yardline[blk_fg_na] = 100 - dat$yards_to_goal[blk_fg_na]
  dat$new_log_ydstogo[blk_fg_na] = log(dat$new_distance[blk_fg_na])
  
  
  
  dat = dat %>% select(new_TimeSecsRem,new_down,new_distance,new_yardline,new_log_ydstogo,turnover) %>%
    mutate_at(vars(new_TimeSecsRem), ~ replace_na(., 0)) %>%
    rename(yards_to_goal=new_yardline)
  colnames(dat) = gsub("new_","",colnames(dat))
  
  ## seems to fail here, figure out why.
  ## doesn't like
  adj_to = (dat$yards_to_goal == 0) & (turnover_ind)
  dat$log_ydstogo[adj_to] = log(10)
  dat$yards_to_goal[adj_to] = 80
  dat$Under_two = dat$TimeSecsRem <= 120
  
  return(dat)
}

### Figure out who is who, so you can attribute players to it.
identify_players <- function(pbp_df) {
  pbp_df = pbp_df %>% mutate(
    passer_name = NA,
    receiver_name = NA,
    rusher_name = NA,
    pass_rusher_name_1 = NA,
    pass_rusher_name_2 = NA,
    force_fumble_player = NA,
    sacked_player_name = NA,
    int_player_name = NA,
    deflect_player_name = NA
  )
  
  pbp_df = pbp_df %>%
    mutate(
      ## Passes - QB
      passer_name = str_split(play_text, "pass") %>% map_chr(., 1),
      passer_name = ifelse(str_detect(play_text, "pass"), passer_name, NA),
      ## all rushes
      rusher_name = str_split(play_text, "run for") %>% map_chr(., 1),
      rusher_name = ifelse(
        is.na(rusher_name),
        str_split(play_text, "rush") %>% map_chr(., 1),
        rusher_name
      ),
      rusher_name = ifelse(
        str_detect(play_text, "rush") |
          str_detect(play_text, "run for"),
        rusher_name,
        NA
      )
    )
  
  ## Passes - WR
  completed_pass = str_detect(pbp_df$play_text, "pass complete to")
  incomplete_pass = str_detect(pbp_df$play_text, "pass incomplete to")
  pbp_df$receiver_name[completed_pass] = str_split(pbp_df$play_text[completed_pass], "pass complete to") %>%
    map_chr(., 2) %>% str_split(., "for") %>% map_chr(., 1)
  pbp_df$receiver_name[incomplete_pass] = str_split(pbp_df$play_text[incomplete_pass], "pass incomplete to") %>%   map_chr(., 2)
  
  ## Defensive plays
  fumble = str_detect(pbp_df$play_text, 'forced by')
  pbp_df$force_fumble_player  <-
    str_split(pbp_df$play_text[fumble], 'forced by') %>% map_chr(., 2) %>% str_split(., ",") %>% map_chr(., 1)
  
  int_td = str_detect(pbp_df$play_text, 'pass intercepted for a TD')
  int = str_detect(pbp_df$play_text, 'pass intercepted') & (!int_td)
}
