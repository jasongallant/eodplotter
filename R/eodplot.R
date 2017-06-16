library(tdmsreader)



#' Get EOD matrix
#' @export
#'
#' @param filename The filename
#' @param channel The channel name, default /'Untitled'/'Dev1/ai0' which is just common in our lab
#' @param prebaseline Subtract baseline pre normalization
#' @param postbaseline Subtract baseline post normalization
#' @param normalize Normalize data to 0-1
#' @param alpha Alpha channel for all EODs plot
#' @param window Window size
#' @param verbose Set verbose output
getEODMatrix <- function(filename, peaks, channel = "/'Untitled'/'Dev1/ai0'", prebaseline = F, postbaseline = F, normalize = F, alpha = F, window = 0.005, verbose = F) {
    m = file(filename, 'rb')
    main = TdmsFile$new(m)
    c = ifelse(is.null(channel), "/'Untitled'/'Dev1/ai0'", channel)
    r = main$objects[[c]]
    if(is.null(r)) {
        stop('Channel not found')
    }
    inc = r$properties[['wf_increment']]
    max = r$number_values * inc
    main$read_data(m, 0, max)
    close(m)

    if(verbose) {
        cat('gathering peak data...\n')
    }
    peakdata = apply(peaks, 1, function(row) {
        start = as.numeric(row[[1]])
        s = start - window / 2
        e = start + window / 2
        sp = s/inc
        ep = e/inc
        dat = r$data[sp:ep]
        t = seq(s, e, by = inc) - s
        t = t[1:length(dat)]

        if(row[[2]] == '-') {
            dat = -dat
        }
        if(prebaseline) {
            dat = dat - mean(dat[1:25])
        }
        if(normalize) {
            dat = (dat - min(dat)) / (max(dat) - min(dat))
        }
        if(postbaseline) {
            dat = dat - mean(dat[1:25])
        }
        # rounding important here to avoid different values being collapsed. significant digits may change on sampling rate of tdms
        data.frame(col = start, time = round(t, digits=5), data = dat)
    })
    if(verbose) {
        cat('combining data frames...\n')
    }
    do.call(rbind, peakdata)
}




#' Plot EODs and find EOD statistics
#' @export
#' @import ggplot2
#'
#' @param filename The filename
#' @param channel The channel name, default /'Untitled'/'Dev1/ai0' which is just common in our lab
#' @param prebaseline Subtract baseline pre normalization
#' @param postbaseline Subtract baseline post normalization
#' @param normalize Normalize data to 0-1
#' @param alpha Alpha channel for all EODs plot
#' @param window Window size
#' @param verbose Set verbose output
plotEod <- function(filename, peaks, channel = "/'Untitled'/'Dev1/ai0'", prebaseline = F, postbaseline = F, normalize = F, alpha = F, window = 0.005, verbose = F) {
    plotdata = getEODMatrix(filename, peaks, channel, prebaseline, postbaseline, normalize, alpha, window, verbose)

    ret = reshape2::acast(plotdata, time ~ col, value.var = 'data', fun.aggregate = mean)
    avg = apply(ret, 1, mean)
    avg = avg[1:(length(avg)-1)]
    data = data.frame(time = as.numeric(names(avg)), val = as.numeric(avg))
    p1pos = which.max(data$val)
    p1 = data[p1pos, ]
    p1_e = plotdata[p1$time == plotdata$time,]
    p2pos = which.min(data$val)
    p2 = data[p2pos, ]
    p2_e = plotdata[p2$time == plotdata$time,]
    leftside = data[1:p1pos, ]
    middle = data[p1pos:p2pos, ]
    rightside = data[p2pos:nrow(data), ]

    baseline = mean(data$val[1:25])
    p0 = NULL
    t1 = NULL
    t2 = NULL
    slope1 = NULL
    slope2 = NULL
    s1 = NULL
    s2 = NULL
    zc1 = NULL
    zc2 = NULL
    for(i in nrow(leftside):1) {
        if(leftside[i, 'val'] < baseline) {
            zc1 = leftside[i,]
            zc1_e = plotdata[zc1$time==plotdata$time, ]
            tzc1 = zc1$time
            p0calculator = leftside[leftside$time >= tzc1-0.0005 & leftside$time <= tzc1,]
            p0 = p0calculator[which.min(p0calculator$val), ]
            p0_e = plotdata[p0$time==plotdata$time, ]
            break
        }
    }
    for(i in nrow(leftside):1) {
        if(leftside[i, 'val'] < baseline + 0.02 * (p1$val - p2$val)) {
            t1 = leftside[i,]
            t1_e = plotdata[t1$time==plotdata$time, ]
            slope1 = leftside[i:nrow(leftside), ]
            break
        }
    }
    for(i in 1:nrow(rightside)) {
        if(rightside[i, 'val'] > baseline - 0.02 * (p1$val - p2$val)) {
            t2 = rightside[i,]
            t2_e = plotdata[t2$time==plotdata$time, ]

            break
        }
    }

    slope1_max = -100000
    for(i in 1:(nrow(slope1)-1)) {
        s = (slope1[i+1, 'val'] - slope1[i, 'val']) / (slope1[i+1, 'time'] - slope1[i, 'time'])
        if(s > slope1_max) {
            slope1_max = s
            s1 = slope1[i,]
            s1_e = plotdata[s1$time==plotdata$time, ]
        }
    }
    slope2_max = 100000
    for(i in 1:(nrow(middle)-1)) {
        s = (middle[i+1, 'val'] - middle[i, 'val']) / (middle[i+1, 'time'] - middle[i, 'time'])
        if(s < slope2_max) {
            slope2_max = s
            s2 = middle[i, ]
            s2_e = plotdata[s2$time==plotdata$time, ]
        }
    }
    for(i in 1:nrow(middle)) {
        if(middle[i, 'val'] < baseline) {
            zc2 = middle[i,]
            zc2_e = plotdata[zc2$time==plotdata$time, ]
            break
        }
    }

    if(!is.null(p0)) landmark_table = data.frame(landmark = 'p0', time = p0$time, val = p0$val, mean = mean(p0_e$data,na.rm=T), sd = sd(p0_e$data,na.rm=T))
    if(!is.null(p1)) landmark_table = rbind(landmark_table, data.frame(landmark = 'p1', time = p1$time, val = p1$val, mean = mean(p1_e$data,na.rm=T), sd = sd(p1_e$data,na.rm=T)))
    if(!is.null(p2)) landmark_table = rbind(landmark_table, data.frame(landmark = 'p2', time = p2$time, val = p2$val, mean = mean(p2_e$data,na.rm=T), sd = sd(p2_e$data,na.rm=T)))
    if(!is.null(t1)) landmark_table = rbind(landmark_table, data.frame(landmark = 't1', time = t1$time, val = t1$val, mean = mean(t1_e$data,na.rm=T), sd = sd(t1_e$data,na.rm=T)))
    if(!is.null(t2)) landmark_table = rbind(landmark_table, data.frame(landmark = 't2', time = t2$time, val = t2$val, mean = mean(t2_e$data,na.rm=T), sd = sd(t2_e$data,na.rm=T)))
    if(!is.null(s1)) landmark_table = rbind(landmark_table, data.frame(landmark = 's1', time = s1$time, val = s1$val, mean = mean(s1_e$data,na.rm=T), sd = sd(s1_e$data,na.rm=T)))
    if(!is.null(s2)) landmark_table = rbind(landmark_table, data.frame(landmark = 's2', time = s2$time, val = s2$val, mean = mean(s2_e$data,na.rm=T), sd = sd(s2_e$data,na.rm=T)))
    if(!is.null(zc1)) landmark_table = rbind(landmark_table, data.frame(landmark = 'zc1', time = zc1$time, val = zc1$val, mean = mean(zc1_e$data,na.rm=T), sd = sd(zc1_e$data,na.rm=T)))
    if(!is.null(zc2)) landmark_table = rbind(landmark_table, data.frame(landmark = 'zc2', time = zc2$time, val = zc2$val, mean = mean(zc2_e$data,na.rm=T), sd = sd(zc2_e$data,na.rm=T)))


    amp1=landmark_table[landmark_table$landmark=='p1',]$val
    amp2=landmark_table[landmark_table$landmark=='p2',]$val
    time2=landmark_table[landmark_table$landmark=='t2',]$time
    time1=landmark_table[landmark_table$landmark=='t1',]$time
    stats = data.frame(
        amplitude=amp1-amp2,
        duration=time2-time1,
        total_eods = nrow(peaks)
    )
    write.csv(landmark_table, paste0(basename(filename), '.landmarks.csv'), quote=F, row.names=F)
    write.csv(stats, paste0(basename(filename), '.stats.csv'), quote=F, row.names=F)





    mtitle = basename(filename)
    if(verbose) {
        cat('plotting average peak...\n')
    }

    png(paste0(basename(filename), '.average.png'), width=1000, height=600)
    p = ggplot(data=plotdata, aes(x=time, y=data)) + stat_summary(aes(y = data), fun.y=mean, geom='line') + ggtitle(mtitle)
    print(p)
    dev.off()

    if(verbose) {
        cat('plotting total peak...\n')
    }
    png(paste0(basename(filename), '.all.png'), width=1000, height=600)
    p = ggplot(data=plotdata, aes(x=time, y=data, group=col)) + geom_line(alpha=alpha) + ggtitle(mtitle)
    print(p)
    dev.off()

    if(verbose) {
        cat('plotting average peak (with landmarks)...\n')
    }

    png(paste0(basename(filename), '.average.landmarks.png'), width=1000, height=600)
    p = ggplot(data=plotdata, aes(x=time, y=data)) + stat_summary(aes(y = data), fun.y=mean, geom='line') + geom_point(data = landmark_table, aes(x=time, y=val, color=landmark), size = 4) + scale_colour_brewer(palette = "Set1") + ggtitle(mtitle)
    print(p)
    dev.off()
}