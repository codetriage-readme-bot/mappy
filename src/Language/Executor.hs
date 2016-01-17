module Language.Executor where

import Debug.Trace
import qualified Data.Set as S
import qualified Data.Map as M
import qualified Data.Either as E

import Language.Ast

data Error =
  MainNotFound
  | RepeatedDefinition String
  | NameNotDefined String
  | WrongNumberOfArguments String Int Int
  | KeyNotFound Expression
  | GiveCalledOnNonMap Expression Expression Expression
  deriving (Show, Eq)

singleError :: a -> Either [a] b
singleError = Left . pure

type FullyEvaluated = Either [Error] Expression
type Env = [(Expression, Expression)]

exec :: [Definition] -> FullyEvaluated
exec defs = do
  checkAgainstRepeatedDefs defs
  (env, mainExpr) <- initialEnvironment defs
  eval env mainExpr

eval :: Env -> Expression -> FullyEvaluated
eval env namedValue@(MappyNamedValue name) = do
  result <- maybe (singleError $ NameNotDefined name) Right (lookup namedValue env)
  eval env result
eval env (MappyApp fn params) = apply env fn params
eval env (MappyLambda args body) = Right $ MappyClosure args body env
eval _ (MappyClosure _ body env) = eval env body
eval env (MappyMap map') = evalKeys (eval env) map'
eval _ value = Right value

evalKeys :: (Expression -> FullyEvaluated) -> M.Map Expression Expression -> FullyEvaluated
evalKeys evaluator map = go [] (M.toList map)
  where
  go pairs [] = Right $ MappyMap $ M.fromList pairs
  go pairs ((key, value):rest) = do
    key' <- evaluator key
    go ((key', value):pairs) rest

apply :: Env -> Expression -> [Expression] -> FullyEvaluated
apply env expr args = apply' env expr args

apply' :: Env -> Expression -> [Expression] -> FullyEvaluated
apply' env (MappyNamedValue "take") (key:map:[]) =
  take' env key map M.lookup
apply' env (MappyNamedValue "take") args =
  singleError $ WrongNumberOfArguments "take" 2 $ length args
apply' env (MappyNamedValue "default-take") (key:map:def:[]) =
  take' env key map (\expr -> Just . M.findWithDefault def expr)
apply' env (MappyNamedValue "default-take") args =
  singleError $ WrongNumberOfArguments "default-take" 3 $ length args
apply' env (MappyNamedValue "give") (key:value:map:[]) = do
  key' <- eval env key
  map' <- eval env map
  value' <- eval env value
  maybe (singleError $ GiveCalledOnNonMap key value' map') Right (mapInsert key' value' map')
    where
    mapInsert k v (MappyMap map) = Just $ MappyMap $ M.insert k v map
    mapInsert _ _ _ = Nothing
apply' env (MappyNamedValue "give") args =
  singleError $ WrongNumberOfArguments "give" 3 $ length args
apply' env nonPrimitive args = eval env nonPrimitive >>= applyOrGet args env >>= eval env

applyOrGet args _ (MappyClosure params body closureEnv) = do
  nextEnv <- extendEnvironment params args closureEnv
  eval nextEnv body
applyOrGet _ env nonClosure = Right nonClosure

evalArguments :: [Expression] -> [Expression] -> Env -> Either [Error] [Expression]
evalArguments names values env = case E.partitionEithers $ map go $ zip names values of
  ([], exprs) -> Right exprs
  (errors, _) -> Left $ concat errors
  where
  go (MappyLazyArgument _, value) = Right $ MappyClosure [] value env
  go (_, value) = eval env value

extendEnvironment :: [Expression] -> [Expression] -> Env -> Either [Error] Env
extendEnvironment names values env = do
  values' <- evalArguments names values env
  Right $ zip (map toNamedValue names) values ++ env
    where
    toNamedValue (MappyLazyArgument name) = MappyNamedValue name
    toNamedValue v = v

take' :: Env -> Expression -> Expression -> (Expression -> M.Map Expression Expression -> Maybe Expression) -> FullyEvaluated
take' env key map f = do
  key' <- eval env key
  map' <- eval env map
  result <- maybe (singleError $ KeyNotFound key') Right (mapLookup f key' map')
  eval env result
    where
    mapLookup f key' (MappyMap map) = f key' map
    mapLookup _ _ _ = Nothing

checkAgainstRepeatedDefs :: [Definition] -> Either [Error] [Definition]
checkAgainstRepeatedDefs defs = go (S.empty, []) defs
  where
  go (_, []) [] = Right defs
  go (_, repeats) [] = Left $ map RepeatedDefinition repeats
  go (seen, repeats) ((MappyDef (MappyNamedValue name) _):rest) = go (S.insert name seen, newRepeats seen name repeats) rest

  newRepeats seen name = (++) (if S.member name seen then [name] else [])

initialEnvironment :: [Definition] -> Either [Error] (Env, Expression)
initialEnvironment = go ([], Nothing)
  where
  go (env, Just m) [] = Right (env, m)
  go (_, Nothing) [] = singleError MainNotFound
  go (env, _) (MappyDef (MappyNamedValue "main") mainBody:rest) = go (env, Just mainBody) rest
  go (env, maybeMain) (MappyDef name body:rest) = go ((name, body):env, maybeMain) rest
