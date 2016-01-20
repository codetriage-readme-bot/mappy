module Language.Ast (
  Definition(..)
  , Expression(..)
  , PrimitiveMap(..)
  , SugaredDefinition(..)
  , SugaredExpression(..)
  ) where

import Language.Primitives.Map

data SugaredDefinition =
  SugaredFnDefinition Expression [Expression] Expression
  deriving (Eq, Show, Ord)

data SugaredExpression =
  SugaredLet [Definition] Expression
  deriving (Eq, Show, Ord)

data Definition =
  MappyDef Expression Expression
  | DefSugar SugaredDefinition
  deriving (Eq, Show, Ord)

data Expression =
  MappyMap (PrimitiveMap Expression)
  | MappyApp Expression [Expression]
  | MappyLambda [Expression] Expression
  | MappyClosure [Expression] Expression [(Expression, Expression)]
  | MappyKeyword String
  | MappyNamedValue String
  | MappyLazyArgument String
  | ExprSugar SugaredExpression
  deriving (Eq, Show, Ord)
