#' @include glmnetUtils.r
NULL

#' @name glmnet
#' @export
glmnet <- function(x, ...)
UseMethod("glmnet")

#' @rdname glmnet
#' @method glmnet default
#' @export
glmnet.default <- function(x, y, ...)
{
    cl <- match.call()
    cl[[1]] <- quote(glmnet::glmnet)
    obj <- glmnet::glmnet(x, y, ...)
    obj$call <- cl
    obj
}


#' Formula interface for elastic net modelling with glmnet
#'
#' @param x For the default method, a matrix of predictor variables.
#' @param y For the default method, a response vector or matrix (for a multinomial response).
#' @param formula A model formula; interaction terms are allowed and will be expanded per the usual rules for linear models.
#' @param data A data frame or matrix containing the variables in the formula.
#' @param family The model family. See [glmnet::glmnet] for how to specify this argument.
#' @param weights An optional vector of case weights to be used in the fitting process. If missing, defaults to an unweighted fit.
#' @param offset An optional vector of offsets, an _a priori_ known component to be included in the linear predictor.
#' @param subset An optional vector specifying the subset of observations to be used to fit the model.
#' @param na.action A function which indicates what should happen when the data contains missing values. For the `predict` method, `na.action = na.pass` will predict missing values with `NA`; `na.omit` or `na.exclude` will drop them.
#' @param drop.unused.levels Should factors have unused levels dropped? Defaults to `FALSE`.
#' @param xlev A named list of character vectors giving the full set of levels to be assumed for each factor.
#' @param alpha The elastic net mixing parameter. See [glmnet::glmnet] for more details.
#' @param sparse Should the model matrix be in sparse format? This can save memory when dealing with many factor variables, each with many levels.
#' @param use.model.frame Should the base [model.frame] function be used when constructing the model matrix? This is the standard method that most R modelling functions use, but has some disadvantages. The default is to avoid `model.frame` and construct the model matrix term-by-term; see [discussion][glmnet.model.matrix].
#' @param relax For `glmnet.formula`, whether to perform a relaxed (non-regularised) fit after the regularised one. Requires glmnet 3.0 or later.
#' @param ... For `glmnet.formula` and `glmnet.default`, other arguments to be passed to [glmnet::glmnet]; for the `predict` and `coef` methods, arguments to be passed to their counterparts in package glmnet.
#'
#' @details
#' The `glmnet` function in this package is an S3 generic with a formula and a default method. The former calls the latter, and the latter is simply a direct call to the `glmnet` function in package glmnet. All the arguments to `glmnet::glmnet` are (or should be) supported.
#'
#' There are two ways in which the matrix of predictors can be generated. The default, with `use.model.frame = FALSE`, is to process the additive terms in the formula independently. With wide datasets, this is much faster and more memory-efficient than the standard R approach which uses the `model.frame` and `model.matrix` functions. However, the resulting model object is not exactly the same as if the standard approach had been used; in particular, it lacks a bona fide [terms] object. If you require interoperability with other packages that assume the standard model object structure, set `use.model.frame = TRUE`. See [discussion][glmnet.model.matrix] for more information on this topic.
#'
#' The `predict` and `coef` methods are wrappers for the corresponding methods in the glmnet package. The former constructs a predictor model matrix from its `newdata` argument and passes that as the `newx` argument to `glmnet:::predict.glmnet`.
#'
#' @section Value:
#' For `glmnet.formula`, an object of class either `glmnet.formula` or `relaxed.formula`, based on the value of the `relax` argument. This is basically the same object created by `glmnet::glmnet`, but with extra components to allow formula usage.
#'
#' @seealso
#' [glmnet::glmnet], [glmnet::predict.glmnet], [glmnet::coef.glmnet], [model.frame], [model.matrix]
#'
#' @examples
#' glmnet(mpg ~ ., data=mtcars)
#'
#' glmnet(Species ~ ., data=iris, family="multinomial")
#'
#' \dontrun{
#'
#' # Leukemia example dataset from Trevor Hastie's website
#' download.file("https://web.stanford.edu/~hastie/glmnet/glmnetData/Leukemia.RData",
#'               "Leukemia.RData")
#' load("Leukemia.Rdata")
#' leuk <- do.call(data.frame, Leukemia)
#' glmnet(y ~ ., leuk, family="binomial")
#' }
#' @rdname glmnet
#' @method glmnet formula
#' @importFrom glmnet glmnet
#' @export
glmnet.formula <- function(formula, data,
                           family=c("gaussian", "binomial", "poisson", "multinomial", "cox", "mgaussian"),
                           alpha=1, ..., weights=NULL, offset=NULL, subset=NULL,
                           na.action=getOption("na.action"), drop.unused.levels=FALSE, xlev=NULL,
                           sparse=FALSE, use.model.frame=FALSE, relax=FALSE)
{
    # must use NSE to get model.frame emulation to work
    cl <- match.call(expand.dots=FALSE)
    cl[[1]] <- if(use.model.frame)
        makeModelComponentsMF
    else makeModelComponents
    xy <- eval.parent(cl)

    if(is.character(family))
        family <- match.arg(family)
    else
    {
        if(utils::packageVersion("glmnet") < package_version("4.0.0"))
            stop("Enhanced family argument requires glmnet version 4.0 or higher", call.=FALSE)
        if(is.function(family))
            family <- family()
        else if(!inherits(family, "family"))
            stop("Invalid family argument; must be either character, function or family object")
    }

    model <- glmnet::glmnet(xy$x, y=xy$y, family=family, weights=xy$weights, offset=xy$offset, alpha=alpha, ...)
    model$call <- match.call()
    model$call[[1]] <- parse(text="glmnetUtils:::glmnet.formula")[[1]]  # needed to make relaxed fitting work
    model$terms <- xy$terms
    model$xlev <- xy$xlev
    model$alpha <- alpha
    model$sparse <- sparse
    model$use.model.frame <- use.model.frame
    model$na.action <- na.action

    # can't pass relax directly to glmnet because of NSE wackiness induced by update()
    if(relax)
    {
        if(utils::packageVersion("glmnet") < package_version("3.0.0"))
            stop("Relaxed fit requires glmnet version 3.0 or higher", call.=FALSE)
        model <- glmnet::relax.glmnet(model, xy$x, family=family, weights=xy$weights, offset=xy$offset, alpha=alpha,
                                      ..., check.args=FALSE)
        class(model) <- c("relaxed.formula", class(model))
    }
    else class(model) <- c("glmnet.formula", class(model))

    model
}


#' @param object For the `predict` and `coef` methods, an object of class `glmnet.formula`.
#' @param newdata For the `predict` method, a data frame containing the observations for which to calculate predictions.
#' @rdname glmnet
#' @importFrom Matrix sparse.model.matrix
#' @export
#' @method predict glmnet.formula
predict.glmnet.formula <- function(object, newdata, offset=NULL, na.action=na.pass, ...)
{
    if(!inherits(object, "glmnet.formula"))
        stop("invalid glmnet.formula object")

    # must use NSE to get model.frame emulation to work
    cl <- match.call(expand.dots=FALSE)
    cl$formula <- delete.response(object$terms)
    cl$data <- cl$newdata
    cl$newdata <- NULL
    cl$xlev <- object$xlev
    cl[[1]] <- if(object$use.model.frame)
        makeModelComponentsMF
    else makeModelComponents

    xy <- eval.parent(cl)
    x <- xy$x
    offset <- xy$offset

    class(object) <- class(object)[-1]
    predict(object, x, offset=offset, ...)
}

#' @rdname glmnet
#' @export
#' @method coef glmnet.formula
coef.glmnet.formula <- function(object, ...)
{
    if(!inherits(object, "glmnet.formula"))
        stop("invalid glmnet.formula object")
    class(object) <- class(object)[-1]
    coef(object, ...)
}


#' @param digits Significant digits in printed output.
#' @param print.deviance.ratios Whether to print the table of deviance ratios, as per [glmnet::print.glmnet].
#' @rdname glmnet
#' @export
#' @method print glmnet.formula
print.glmnet.formula <- function(x, digits=max(3, getOption("digits") - 3), print.deviance.ratios=FALSE, ...)
{
    cat("Call:\n")
    dput(x$call)
    cat("\nModel fitting options:")
    cat("\n    Sparse model matrix:", x$sparse)
    cat("\n    Use model.frame:", x$use.model.frame)
    cat("\n    Alpha:", x$alpha)
    cat("\n    Lambda summary:\n")
    print(summary(x$lambda))
    if(print.deviance.ratios)
    {
        cat("\nDeviance ratios:\n")
        print(cbind(Df=x$df, `%Dev`=signif(x$dev.ratio, digits), Lambda=signif(x$lambda, digits)))
    }
    cat("\n")
    invisible(x)
}


#' @rdname glmnet
#' @export
#' @method print relaxed.formula
print.relaxed.formula <- function(x, digits=max(3, getOption("digits") - 3), print.deviance.ratios=FALSE, ...)
{
    print.glmnet.formula(x)
    cat("Relaxed fit in component $relaxed\n")
    invisible(x)
}


#' @rdname glmnet
#' @export
#' @method predict relaxed.formula
predict.relaxed.formula <- function(object, newdata, offset=NULL, na.action=na.pass, ...)
{
    if(!inherits(object, "relaxed.formula"))
        stop("invalid relaxed.formula object")

    # must use NSE to get model.frame emulation to work
    cl <- match.call(expand.dots=FALSE)
    cl$formula <- delete.response(object$terms)
    cl$data <- cl$newdata
    cl$newdata <- NULL
    cl$xlev <- object$xlev
    cl[[1]] <- if(object$use.model.frame)
        makeModelComponentsMF
    else makeModelComponents

    xy <- eval.parent(cl)
    x <- xy$x
    offset <- xy$offset

    class(object) <- class(object)[-1]
    predict(object, x, offset=offset, ...)
}

#' @rdname glmnet
#' @export
#' @method coef relaxed.formula
coef.relaxed.formula <- function(object, ...)
{
    if(!inherits(object, "relaxed.formula"))
        stop("invalid relaxed.formula object")
    class(object) <- class(object)[-1]
    coef(object, ...)
}
